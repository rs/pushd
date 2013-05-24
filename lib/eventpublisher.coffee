events = require 'events'
Payload = require('./payload').Payload
logger = require 'winston'

class EventPublisher extends events.EventEmitter
    constructor: (@redis, @pushServices, @statistics) ->

    publish: (event, data, cb) ->
        try
            payload = new Payload(data)
            payload.event = event
        catch e
            # Invalid payload (empty, missing key or invalid key format)
            logger.error 'Invalid payload ' + e
            cb(-1) if cb
            return

        @.emit(event.name, event, payload)

        event.exists (exists) =>
            if not exists
                logger.verbose "Tried to publish to a non-existing event #{event.name}"
                cb(0) if cb
                return

            try
                # Do not compile templates before to know there's some subscribers for the event
                # and do not start serving subscribers if payload won't compile
                payload.compile()
            catch e
                logger.error "Invalid payload, template doesn't compile"
                cb(-1) if cb
                return

            logger.verbose "Pushing message for event #{event.name}"
            logger.silly 'Title: ' + payload.localizedTitle('en')
            logger.silly payload.localizedMessage('en')

            protoCounts = {}
            event.forEachSubscribers (subscriber, subOptions, done) =>
                # action
                subscriber.get (info) =>
                    if info?.proto?
                        if protoCounts[info.proto]?
                            protoCounts[info.proto] += 1
                        else
                            protoCounts[info.proto] = 1

                @pushServices.push(subscriber, subOptions, payload, done)
            , (totalSubscribers) =>
                # finished
                logger.verbose "Pushed to #{totalSubscribers} subscribers"
                for proto, count of protoCounts
                    logger.verbose "#{count} #{proto} subscribers"
                    
                    # update global stats
                    @statistics.increasePublishedCount(proto, count)

                if totalSubscribers > 0
                    # update some event stats
                    event.log =>
                        cb(totalSubscribers) if cb
                else
                    # if there is no subscriber, cleanup the event
                    event.delete =>
                        cb(0) if cb

exports.EventPublisher = EventPublisher