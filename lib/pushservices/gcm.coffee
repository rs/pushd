gcm = require 'node-gcm'

class PushServiceGCM
    tokenFormat: /^[a-zA-Z0-9_-]+$/
    validateToken: (token) ->
        if PushServiceGCM::tokenFormat.test(token)
            return token

    constructor: (conf, @logger, tokenResolver) ->
        conf.concurrency ?= 10
        @driver = new gcm.Sender(conf.key)

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = new gcm.Message()
            note.collapseKey = payload.event.name
            if subOptions?.ignore_message isnt true
                if title = payload.localizedTitle(info.lang)
                    note.addData 'title', title
                if message = payload.localizedMessage(info.lang)
                    note.addData 'message', message
            note.addData(key, value) for key, value of payload.data

            # TODO: handle GCM multicast message
            @driver.send note, [info.token], 4, (result) =>
                if result.messageId
                    # if result.canonicalRegistrationId
                        # TODO: update subscriber token
                else
                    if result.errorCode is "NotRegistered" or result.errorCode is "InvalidRegistration"
                        @logger?.warn("GCM Automatic unregistration for subscriber #{subscriber.id}")
                        subscriber.delete()
                    else
                        @logger?.error("GCM Error: #{result.errorCode}")

exports.PushServiceGCM = PushServiceGCM
