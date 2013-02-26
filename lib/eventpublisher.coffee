events = require 'events'
Payload = require('./payload').Payload

class EventPublisher extends events.EventEmitter
    constructor: (@pushServices) ->

    publish: (event, data, cb) ->
        try
            payload = new Payload(data)
            payload.event = event
        catch e
            # Invalid payload (empty, missing key or invalid key format)
            cb(-1) if cb
            return

        @.emit(event.name, event, payload)

        event.exists (exists) =>
            if not exists
                cb(0) if cb
                return

            try
                # Do not compile templates before to know there's some subscribers for the event
                # and do not start serving subscribers if payload won't compile
                payload.compile()
            catch e
                # Invalid payload (templates doesn't compile)
                cb(-1) if cb
                return

            event.forEachSubscribers (subscriber, subOptions, done) =>
                # action
                @pushServices.push(subscriber, subOptions, payload, done)
            , (totalSubscribers) =>
                # finished
                if totalSubscribers > 0
                    # update some event' stats
                    event.log =>
                        cb(totalSubscribers) if cb
                else
                    # if there is no subscriber, cleanup the event
                    event.delete =>
                        cb(0) if cb

exports.EventPublisher = EventPublisher