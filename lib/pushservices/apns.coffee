apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    constructor: (conf, @logger, tokenResolver) ->
        conf.errorCallback = (errCode, note) =>
            @logger?.error("APNS Error #{besn}: #{note}")

        # The APN library decided to change the default version of those variables in 1.5.1
        # Maintain the previous defaults in order not to break backward compat.
        # conf['gateway'] ||= 'gateway.push.apple.com'
        conf['address'] ||= 'api.push.apple.com'
        try
          @driver = new apns.Provider(conf)
          @payloadFilter = conf.payloadFilter
          conf.address = "api.push.apple.com"
          @conf = conf
        catch error
          console.error "The error is ... #{error} and the cert is ... #{conf.cert}"
        # @feedback = new apns.Feedback(conf)
        # # Handle Apple Feedbacks
        # @feedback.on 'feedback', (feedbackData) =>
        #     @logger?.debug("APNS feedback returned #{feedbackData.length} devices")
        #     feedbackData.forEach (item) =>
        #         tokenResolver 'apns', item.device.toString(), (subscriber) =>
        #             subscriber?.get (info) =>
        #                 if info.updated < item.time
        #                     @logger?.warn("APNS Automatic unregistration for subscriber #{subscriber.id}")
        #                     subscriber.delete()


    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = new apns.Notification()
            if subOptions?.ignore_message isnt true and alert = payload.localizedMessage(info.lang)
                note.alert = alert

            badge = parseInt(payload.badge || info.badge)
            if payload.incrementBadge
                badge += 1

            category = payload.category
            contentAvailable = payload.contentAvailable

            if not contentAvailable? and @conf.contentAvailable?
              contentAvailable = @conf.contentAvailable

            if not category? and @conf.category?
              category = @conf.category
            # never set the badge if contentAvailable is true
            # if contentAvailable
              # badge = null
            if not contentAvailable
              note.badge = badge
            note.pushType = 'alert'
            note.sound = payload.sound
            note.topic = info.proto.split("apns-").join("")
            note.category = category
            note.contentAvailable = contentAvailable
            if @payloadFilter?
                for key, val of payload.data
                    note.payload[key] = val if key in @payloadFilter
            else
                note.payload = payload.data
            @driver.send(note, info.token).then (response) ->
                        console.log "The response from sending a push is #{JSON.stringify response}"
                    .catch (error) ->
                        console.error "The error from sending a push is #{error}"
            # On iOS we have to maintain the badge counter on the server
            if payload.incrementBadge? and not contentAvailable?
                subscriber.incr 'badge'

exports.PushServiceAPNS = PushServiceAPNS
