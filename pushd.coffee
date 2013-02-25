express = require 'express'
dgram = require 'dgram'
zlib = require 'zlib'
url = require 'url'
Netmask = require('netmask').Netmask
redis = require('redis').createClient()
settings = require './settings'
Subscriber = require('./lib/subscriber').Subscriber
Event = require('./lib/event').Event
PushServices = require('./lib/pushservices').PushServices
Payload = require('./lib/payload').Payload
logger = console

createSubscriber = (fields, cb) ->
    throw new Error("Invalid value for `proto'") unless service = pushservices.getService(fields.proto)
    throw new Error("Invalid value for `token'") unless fields.token = service.validateToken(fields.token)
    Subscriber::create(redis, fields, cb)

tokenResolver = (proto, token, cb) ->
    Subscriber::getInstanceFromToken redis, proto, token, cb

pushservices = new PushServices()
for name, conf of settings when conf.enabled
    logger.log "Registering push service: #{name}"
    pushservices.addService(name, new conf.class(conf, logger, tokenResolver))

app = express()

app.configure ->
    app.use(express.logger(':method :url :status')) if settings.server?.access_log
    app.use(express.limit('1mb')) # limit posted data to 1MB
    app.use(express.bodyParser())
    app.use(app.router)

app.param 'subscriber_id', (req, res, next, id) ->
    try
        req.subscriber = new Subscriber(redis, req.params.subscriber_id)
        delete req.params.subscriber_id
        next()
    catch error
        res.json error: error.message, 400

getEventFromId = (id) ->
    return new Event(redis, pushservices, id)

testSubscriber = (subscriber) ->
    pushservices.push(subscriber, null, new Payload({msg: "Test", "data.test": "ok"}))

app.param 'event_id', (req, res, next, id) ->
    try
        req.event = getEventFromId(req.params.event_id)
        delete req.params.event_id
        next()
    catch error
        res.json error: error.message, 400

authorize = (realm) ->
    if allow_from = settings.server?.acl?[realm]
        networks = []
        for network in allow_from
            networks.push new Netmask(network)
        return (req, res, next) ->
            if remoteAddr = req.socket and (req.socket.remoteAddress or (req.socket.socket and req.socket.socket.remoteAddress))
                for network in networks
                    if network.contains(remoteAddr)
                        next()
                        return
            res.json error: 'Unauthorized', 403
    else
        return (req, res, next) -> next()

require('./lib/api').setupRestApi(app, createSubscriber, getEventFromId, authorize, testSubscriber)

port = settings?.server?.tcp_port ? 80
app.listen port
logger.log "Listening on port #{port}"


# UDP Event API
udpApi = dgram.createSocket("udp4")

event_route = /^\/event\/([a-zA-Z0-9:._-]{1,100})$/
udpApi.checkaccess = authorize('publish')
udpApi.on 'message', (msg, rinfo) ->
    zlib.unzip msg, (err, msg) =>
        if err or not msg.toString()
            logger.error("UDP Cannot decode message: #{err}")
            return
        [method, msg] = msg.toString().split(/\s+/, 2)
        if not msg then [msg, method] = [method, 'POST']
        req = url.parse(msg ? '', true)
        method = method.toUpperCase()
        # emulate an express route middleware call
        @checkaccess {socket: remoteAddress: rinfo.address}, {json: -> logger.log("UDP/#{method} #{req.pathname} 403")}, ->
            status = 404
            if m = req.pathname?.match(event_route)
                try
                    event = new Event(redis, pushservices, m[1])
                    status = 204
                    switch method
                        when 'POST' then event.publish(req.query)
                        when 'DELETE' then event.delete()
                        else status = 404
                catch error
                    logger.error(error.stack)
                    return
            logger.log("UDP/#{method} #{req.pathname} #{status}") if settings.server?.access_log

udpApi.bind settings?.server?.udp_port ? 80
