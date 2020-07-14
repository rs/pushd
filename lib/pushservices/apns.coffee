apns = require 'apn'

class PushServiceAPNS
    tokenFormat: /^[0-9a-f]{64}$/i
    validateToken: (token) ->
        if PushServiceAPNS::tokenFormat.test(token)
            return token.toLowerCase()

    constructor: (conf, @logger, tokenResolver) ->
        conf.errorCallback = (errCode, note) =>
            logger?.error("APNS Error #{JSON.stringify errCode}: #{note} and the cert is ... #{conf.cert}")
        # These should be provided in the certificate configuration. Keeping it in case of debugging a sandbox cert.
        conf['address'] ||= 'api.push.apple.com'
        try
          @driver = new apns.Provider(conf)
          @payloadFilter = conf.payloadFilter
          # These should be provided in the certificate configuration. Keeping it in case of debugging a sandbox cert.
          conf.address = "api.push.apple.com"
          @conf = conf
        catch error
          console.error "The error is ... #{error} and the cert is ... #{conf.cert}"

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

            if not contentAvailable? and @conf? and @conf.contentAvailable?
              contentAvailable = @conf.contentAvailable

            if not category? and @conf? and @conf.category?
              category = @conf.category
            # never set the badge if contentAvailable is true
            # if contentAvailable
              # badge = null
            note.priority = 5
            if not contentAvailable
              note.priority = 10
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
            if @driver?
              @driver.send(note, info.token).then (response) ->
                          console.log "The response from sending a push is #{JSON.stringify response} Subscriber ID: #{JSON.stringify subscriber.id}"
                        .catch (error) ->
                          console.error "The error from sending a push is #{error} Subscriber ID: #{JSON.stringify subscriber.id}"
            else
              console.error "Driver is not set. Subscriber ID: #{JSON.stringify subscriber.id}"
            # On iOS we have to maintain the badge counter on the server
            if payload.incrementBadge? and not contentAvailable?
                subscriber.incr 'badge'

exports.PushServiceAPNS = PushServiceAPNS
