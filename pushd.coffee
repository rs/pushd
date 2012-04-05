express = require 'express'
dgram = require 'dgram'
url = require 'url'
Netmask = require('netmask').Netmask
redis = require('redis').createClient()
subscriber = require './lib/subscriber'
event = require './lib/event'
settings = require './settings'
logger = console
PushServices = require('./lib/pushservices').PushServices

pushservices = new PushServices()
for name, conf of settings when conf.enabled
    pushservices.addService(name, new conf.class(conf, logger))

app = express.createServer()

app.configure ->
    app.use(express.logger(':method :url :status')) if settings.server?.access_log
    app.use(express.limit('1mb')) # limit posted data to 1MB
    app.use(express.bodyParser())
    app.use(app.router)

app.param 'subscriber_id', (req, res, next, id) ->
    try
        req.subscriber = subscriber.getSubscriber(redis, req.params.subscriber_id)
        delete req.params.id
        next()
    catch error
        res.json error: error.message, 400

app.param 'event_id', (req, res, next, id) ->
    try
        req.event = event.getEvent(redis, pushservices, req.params.event_id)
        delete req.params.event_id
        next()
    catch error
        res.json error: error.message, 400

createSubscriber = (fields, cb) ->
    throw new Error("Invalid value for `proto'") unless service = pushservices.getService(fields.proto)
    throw new Error("Invalid value for `token'") unless fields.token = service.validateToken(fields.token)
    return subscriber.createSubscriber(redis, fields, cb)

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

require('./lib/api').setupRestApi(app, createSubscriber, authorize)

app.listen 80


# UDP Event API
udpApi = dgram.createSocket("udp4")

event_route = /^\/event\/([a-zA-Z0-9:._-]{1,100})$/
udpApi.checkaccess = authorize('publish')
udpApi.on 'message', (msg, rinfo) ->
    req = url.parse(msg.toString(), true)
    # emulate an express route middleware call
    @checkaccess {socket: remoteAddress: rinfo.address}, {json: -> logger.log("UDP #{req.pathname} 403")}, ->
        if m = req.pathname.match(event_route)
            try
                event.getEvent(redis, pushservices, m[1]).publish(req.query)
                logger.log("UDP #{req.pathname} 204") if settings.server?.access_log
            catch error
                logger.error(error.stack)
        else
            logger.log("UDP #{req.pathname} 404") if settings.server?.access_log

udpApi.bind 80

# Handle Apple Feedbacks
apns = require 'apn'
options = settings.apns
options.feedback = (time, apnsSubscriber) ->
    subscriber.getSubscriberFromToken redis, 'apns', apnsSubscriber.hexToken(), (subscriber) ->
        subscriber?.get (info) ->
            if info.updated < time
                logger.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
                subscriber.delete()
feedback = new apns.Feedback(options)