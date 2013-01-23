apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    constructor: (conf, @logger, tokenResolver) ->
        conf.errorCallback = (errCode, note) =>
            @logger?.error("APNS Error #{errCode} for subscriber #{note?.device?.subscriberId}")
        @driver = new apns.Connection(conf)

        # Handle Apple Feedbacks
        conf.feedback = (time, apnsSubscriber) ->
            tokenResolver 'apns', apnsSubscriber.hexToken(), (subscriber) =>
                subscriber?.get (info) ->
                    if info.updated < time
                        @logger.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
                        subscriber.delete()
        @feedback = new apns.Feedback(conf)


    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = new apns.Notification()
            note.device = new apns.Device(info.token)
            note.device.subscriberId = subscriber.id # used for error logging
            if subOptions?.ignore_message isnt true and alert = payload.localizedMessage(info.lang)
                note.alert = alert
            note.badge = badge if not isNaN(badge = parseInt(info.badge) + 1)
            note.sound = payload.sound
            note.payload = payload.data
            @driver.sendNotification note
            # On iOS we have to maintain the badge counter on the server
            subscriber.incr 'badge'

exports.PushServiceAPNS = PushServiceAPNS
