event = require './event'
async = require 'async'
apns = require 'apn'
c2dm = require 'c2dm'
#mpns = require 'mpns'

class PushServiceAPNS
    constructor: (conf, @logger) ->
        conf.errorCallback = (errCode, note) =>
            @logger?.error("APNS Error #{errCode} for Subscriber #{note?.Subscriber?.id}")
        @driver = new apns.Connection(conf)

    push: (Subscriber, subOptions, payload) ->
        Subscriber.get (info) =>
            note = new apns.Notification()
            note.Subscriber = new apns.Subscriber(info.regid)
            note.Subscriber.id = Subscriber.id # used for error logging
            if not (subOptions & event.OPTION_IGNORE_MESSAGE) and alert = payload.localizedMessage(info.lang) 
                note.alert = alert
            note.badge = badge if not isNaN(badge = parseInt(info.badge) + 1)
            note.sound = payload.sound
            note.payload = payload.data
            @driver.sendNotification note
            # On iOS we have to maintain the badge counter on the server
            Subscriber.incr 'badge'


class PushServiceC2DM
    constructor: (conf, @logger) ->
        conf.concurrency ?= 10
        conf.keepAlive = true
        @driver = new c2dm.C2DM(conf)
        @driver.login (err, token) =>
            if err then throw Error(err)
            [queuedTasks, @queue] = [@queue, async.queue((=> @_pushTask.apply(@, arguments)), conf.concurrency)]
            for task in queuedTasks
                @queue.push task
        # Queue into an array waiting for C2DM login to complete
        @queue = []

    push: (Subscriber, subOptions, payload) ->
        @queue.push
            Subscriber: Subscriber,
            subOptions: subOptions,
            payload: payload

    _pushTask: (task, done) ->
        task.Subscriber.get (info) =>
            note =
                registration_id: info.regid
                collapse_key: task.payload.event.name
            if not (task.subOptions & event.OPTION_IGNORE_MESSAGE)
                if title = task.payload.localizedTitle(info.lang) 
                    note['data.title'] = title
                if message = task.payload.localizedMessage(info.lang) 
                    note['data.message'] = message
            note["data.#{key}"] = value for key, value of task.payload.data
            @driver.send note, (err, msgid) =>
                done()
                if err in ['InvalidRegistration', 'NotRegistered']
                    # Handle C2DM API feedback about no longer or invalid registrations
                    @logger?.warn("C2DM Automatic unregistration for Subscriber #{task.Subscriber.id}")
                    task.Subscriber.delete()
                else if err
                    @logger?.error("C2DM Error #{err} for Subscriber #{task.Subscriber.id}")


class PushServiceMPNS
    constructor: (@conf, @logger) ->

    push: (Subscriber, subOptions, payload) ->
        # TO BE IMPLEMENTED


class PushServices
    services: {}

    addService: (protocol, service) ->
        @services[protocol] = service

    push: (Subscriber, subOptions, payload, cb) ->
        Subscriber.get (info) =>
            if info then @services[info.proto]?.push(Subscriber, subOptions, payload)
            cb() if cb

exports.PushServices = PushServices

exports.getPushServices = (conf, logger) ->
    services = new PushServices()
    services.addService('apns', new PushServiceAPNS(conf.apns, logger)) if conf.apns
    services.addService('c2dm', new PushServiceC2DM(conf.c2dm, logger)) if conf.c2dm
    services.addService('mpns', new PushServiceMPNS(conf.mpns, logger)) if conf.mpns
    return services
