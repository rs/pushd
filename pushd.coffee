express = require 'express'
dgram = require 'dgram'
url = require 'url'
redis = require('redis').createClient()
device = require './lib/device'
event = require './lib/event'
settings = require './settings'
logger = console
pushservices = require('./lib/pushservices').getPushServices(settings, logger)


app = express.createServer()

app.configure ->
    app.use(express.logger(':method :url :status')) if settings.server?.access_log
    app.use(express.limit('1mb')) # limit posted data to 1MB
    app.use(express.bodyParser())
    app.use(app.router)

app.param 'device_id', (req, res, next, id) ->
    try
        req.device = device.getDevice(redis, req.params.device_id)
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

createDevice = (fields, cb) ->
    device.createDevice redis, fields, cb

require('./lib/api').setupRestApi(app, createDevice)

app.listen 80


# UDP Event API
udpApi = dgram.createSocket("udp4")

event_route = /^\/event\/([a-zA-Z0-9:._-]{1,100})$/
udpApi.on 'message', (msg, rinfo) ->
    req = url.parse(msg.toString(), true)
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
options.feedback = (time, apnsDevice) ->
    device.getDeviceFromRegId redis, 'apns', apnsDevice.hexToken(), (device) ->
        device?.get (info) ->
            if info.updated < time
                logger.warn("APNS Automatic unregistration for device #{device.id}")
                device.delete()
feedback = new apns.Feedback(options)