apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    autoIncrementBadge: yes

    constructor: (conf, @logger, tokenResolver) ->
        @autoIncrementBadge = conf.autoIncrementBadge if !!conf.autoIncrementBadge
        conf.errorCallback = (errCode, note) =>
            @logger?.error("APNS Error #{errCode} for subscriber #{note?.device?.subscriberId}")
        @driver = new apns.Connection(conf)

        @payloadFilter = conf.payloadFilter

        # Handle Apple Feedbacks
        conf.feedback = (time, tokenBuffer) =>
            tokenResolver 'apns', tokenBuffer.toString(), (subscriber) =>
                subscriber?.get (info) ->
                    if info.updated < time
                        @logger?.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
                        subscriber.delete()
        @feedback = new apns.Feedback(conf)


    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = new apns.Notification()
            note.device = new apns.Device(info.token)
            note.device.subscriberId = subscriber.id # used for error logging
            if subOptions?.ignore_message isnt true and alert = payload.localizedMessage(info.lang)
                note.alert = alert
            increment = if @autoIncrementBadge then 1 else 0
            note.badge = badge if not isNaN(badge = parseInt(info.badge) + increment)
            note.sound = payload.sound
            if @payloadFilter?
                for key, val of payload.data
                    note.payload[key] = val if key in @payloadFilter
            else
                note.payload = payload.data
            @driver.sendNotification note
            # On iOS we have to maintain the badge counter on the server
            subscriber.incr 'badge' if @autoIncrementBadge

exports.PushServiceAPNS = PushServiceAPNS
