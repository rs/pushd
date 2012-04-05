subscriber = require './subscriber'
async = require 'async'
Payload = require('./payload').Payload


class Event
    OPTION_IGNORE_MESSAGE: 1
    name_format: /^[a-zA-Z0-9:._-]{1,100}$/

    constructor: (@redis, @pushservices, @name) ->
        throw new Error('Invalid event name') if not Event::name_format.test @name
        @key = "event:#{@name}"

    info: (cb) ->
        return until cb
        @redis.multi()
            # event info
            .hgetall(@key)
            # subscribers total
            .zcard("#{@key}:devs")
            .exec (err, results) =>
                if (f for own f of results[0]).length
                    info = {total: results[1]}
                    # transform numeric value to number type
                    for own key, value of results[0]
                        num = parseInt(value)
                        info[key] = if num + '' is value then num else value
                    cb(info)
                else
                    cb(null)

    publish: (data, cb) ->
        try
            payload = new Payload(data)
            payload.event = @
        catch e
            # Invalid payload (empty, missing key or invalid key format)
            cb(-1) if cb
            return

        @redis.sismember "events", @name, (err, exists) =>
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

            @forEachSubscribers (subscriber, subOptions, done) =>
                # action
                @pushservices.push(subscriber, subOptions, payload, done)
            , (totalSubscribers) =>
                # finished
                if totalSubscribers > 0
                    # update some event' stats
                    @redis.multi()
                        # account number of sent notification since event creation
                        .hincrby(@key, "total", 1)
                        # store last notification date for this event
                        .hset(@key, "last", Math.round(new Date().getTime() / 1000))
                        .exec =>
                            cb(totalSubscribers) if cb
                else
                    # if there is no subscriber, cleanup the event
                    @delete =>
                        cb(0) if cb

    delete: (cb) ->
        @forEachSubscribers (subscriber, subOptions, done) =>
            # action
            subscriber.removeSubscription(@, done)
        , =>
            # finished
            @redis.multi()
                # delete event's info hash
                .del(@key)
                # remove event from global event list
                .srem("events", @name)
                .exec ->
                    cb() if cb

    # Performs an action on each subscriber subsribed to this event
    forEachSubscribers: (action, finished) ->
        if @name is 'broadcast'
            # if event is broadcast, do not treat score as subscription option, ignore it
            performAction = (subscriberId, subOptions) =>
                return (done) =>
                    action(subscriber.getSubscriber(@redis, subscriberId), 0, done)
        else
            performAction = (subscriberId, subOptions) =>
                return (done) =>
                    action(subscriber.getSubscriber(@redis, subscriberId), subOptions, done)

        subscribersKey = if @name is 'boardcast' then 'subscribers' else "#{@key}:devs"
        page = 0
        perPage = 100
        total = 0
        async.whilst =>
            # test if we got less items than requested during last request
            # if so, we reached to end of the list
            return page * perPage == total
        , (done) =>
            # treat subscribers by packs of 100 with async to prevent from blocking the event loop
            # for too long on large subscribers lists
            @redis.zrange subscribersKey, (page++ * perPage), (page * perPage + perPage), 'WITHSCORES', (err, subscriberIdsAndOptions) =>
                tasks = []
                for id, i in subscriberIdsAndOptions by 2
                    tasks.push performAction(id, subscriberIdsAndOptions[i + 1])
                async.series tasks, =>
                    total += subscriberIdsAndOptions.length / 2
                    done()
        , =>
            # all done
            finished(total) if finished


exports.getEvent = (redis, pushservices, eventName) ->
    return new Event(redis, pushservices, eventName)
