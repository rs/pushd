apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    constructor: (conf, @logger, tokenResolver) ->
        conf.errorCallback = (errCode, note) =>
            @logger?.error("APNS Error #{errCode}: #{note}")

        # The APN library decided to change the default version of those variables in 1.5.1
        # Maintain the previous defaults in order not to break backward compat.
        conf['gateway'] ||= 'gateway.push.apple.com'
        conf['address'] ||= 'feedback.push.apple.com'
        @driver = new apns.Connection(conf)

        @payloadFilter = conf.payloadFilter
        
        @conf = conf

        @feedback = new apns.Feedback(conf)
        # Handle Apple Feedbacks
        @feedback.on 'feedback', (feedbackData) =>
            @logger?.debug("APNS feedback returned #{feedbackData.length} devices")
            feedbackData.forEach (item) =>
                tokenResolver 'apns', item.device.toString(), (subscriber) =>
                    subscriber?.get (info) =>
                        if info.updated < item.time
                            @logger?.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
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
            
            category = payload.category
            contentAvailable = payload.contentAvailable

            if not contentAvailable? and @conf.contentAvailable?
              contentAvailable = @conf.contentAvailable

            if not category? and @conf.category?
              category = @conf.category

            note.badge = badge if not isNaN(badge)
            note.sound = payload.sound
            note.category = category
            note.contentAvailable = contentAvailable
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
