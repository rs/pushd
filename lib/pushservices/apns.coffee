apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    constructor: (conf, @logger, tokenResolver, @failCallback) ->
        conf.errorCallback = (errCode, note, device) =>
            @logger?.error("APNS Error #{errCode} for subscriber #{device?.subscriberId}")
            @failCallback()
        @driver = new apns.Connection(conf)

        @payloadFilter = conf.payloadFilter

        @feedback = new apns.Feedback(conf)
        # Handle Apple Feedbacks
        @feedback.on 'feedback', (feedbackData) =>
            @logger?.debug("APNS feedback returned #{feedbackData.length} devices")
            feedbackData.forEach (item) =>
                tokenResolver 'apns', item.device.toString(), (subscriber) =>
                    subscriber?.get (info) =>
                        if info.updated < item.time
                            @logger?.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
                            @failCallback()
                            subscriber.delete()


    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = new apns.Notification()
            device = new apns.Device(info.token)
            device.subscriberId = subscriber.id # used for error logging
            if subOptions?.ignore_message isnt true and alert = payload.localizedMessage(info.lang)
                note.alert = alert

            badge = parseInt(info.badge)
            if payload.incrementBadge
                badge += 1

            note.badge = badge if not isNaN(badge)
            note.sound = payload.sound
            if @payloadFilter?
                for key, val of payload.data
                    note.payload[key] = val if key in @payloadFilter
            else
                note.payload = payload.data
            @driver.pushNotification note, device
            # On iOS we have to maintain the badge counter on the server
            if payload.incrementBadge
                subscriber.incr 'badge'

exports.PushServiceAPNS = PushServiceAPNS
