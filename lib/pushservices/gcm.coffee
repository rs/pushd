gcm = require 'node-gcm'

class PushServiceGCM
    tokenFormat: /^[a-zA-Z0-9_-]+$/
    validateToken: (token) ->
        if PushServiceGCM::tokenFormat.test(token)
            return token

    constructor: (conf, @logger, tokenResolver, @failCallback) ->
        conf.concurrency ?= 10
        @driver = new gcm.Sender(conf.key)
        @multicastQueue = {}

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            messageKey = "#{payload.id}-#{info.lang or 'int'}-#{!!subOptions?.ignore_message}"

            # Multicast supports up to 1000 subscribers
            if messageKey of @multicastQueue and @multicastQueue[messageKey].tokens.length >= 1000
                @.send messageKey

            if messageKey of @multicastQueue
                @multicastQueue[messageKey].tokens.push(info.token)
                @multicastQueue[messageKey].subscribers.push(subscriber)
            else
                note = new gcm.Message()
                note.collapseKey = payload.event?.name
                if subOptions?.ignore_message isnt true
                    if title = payload.localizedTitle(info.lang)
                        note.addData 'title', title
                    if message = payload.localizedMessage(info.lang)
                        note.addData 'message', message
                note.addData(key, value) for key, value of payload.data
                @multicastQueue[messageKey] = {tokens: [info.token], subscribers: [subscriber], note: note}

                # Give half a second for tokens to accumulate
                @multicastQueue[messageKey].timeoutId = setTimeout (=> @.send(messageKey)), 500

    send: (messageKey) ->
        message = @multicastQueue[messageKey]
        delete @multicastQueue[messageKey]
        clearTimeout message.timeoutId

        @driver.send message.note, message.tokens, 4, (err, multicastResult) =>
            if not multicastResult?
                @failCallback 'gcm'
                @logger?.error("GCM Error: empty response")
            else if 'results' of multicastResult
                for result, i in multicastResult.results
                    @.handleResult result, message.subscribers[i]
            else
                # non multicast result
                @handleResult multicastResult, message.subscribers[0]

    handleResult: (result, subscriber) ->
        if result.messageId or result.message_id
            # if result.canonicalRegistrationId
                # TODO: update subscriber token
        else
            error = result.error or result.errorCode
            @failCallback 'gcm'
            if error is "NotRegistered" or error is "InvalidRegistration"
                @logger?.warn("GCM Automatic unregistration for subscriber #{subscriber.id}")
                subscriber.delete()
            else
                @logger?.error("GCM Error: #{error}")



exports.PushServiceGCM = PushServiceGCM
