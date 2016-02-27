async = require 'async'
logger = require 'winston'

class Event
    OPTION_IGNORE_MESSAGE: 1
    name_format: /^[a-zA-Z0-9@:._-]{1,100}$/
    unicast_format: /^unicast:(.+)$/

    constructor: (@redis, @name) ->
        throw new Error("Missing redis connection") if not @redis?
        throw new Error('Invalid event name ' + @name) if not Event::name_format.test @name
        @key = "event:#{@name}"

    info: (cb) ->
        return until cb
        @redis.multi()
            # event info
            .hgetall(@key)
            # subscribers total
            .zcard("#{@key}:subs")
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

    unicastSubscriber: ->
        Subscriber = require('./subscriber').Subscriber
        if (matches = Event::unicast_format.exec @name)?
            subscriberId = matches[1]
            new Subscriber(@redis, subscriberId)
        else
            null

    exists: (cb) ->
        if @name is 'broadcast'
            cb(true)
        else if (subscriber = @unicastSubscriber())?
            subscriber.get (fields) =>
                cb(fields?)
        else
            @redis.sismember "events", @name, (err, exists) =>
                cb(exists)

    delete: (cb) ->
        logger.verbose "Deleting event #{@name}"

        performDelete = () =>
            @redis.multi()
                # delete event's info hash
                .del(@key)
                # remove event from global event list
                .srem("events", @name)
                .exec (err, results) ->
                    cb(results[1] > 0) if cb


        if @unicastSubscriber()?
            performDelete()
        else
            @forEachSubscribers (subscriber, subOptions, doneCb) =>
                # action
                subscriber.removeSubscription(@, doneCb)
                # subscriberCount += 1
            , (totalSubscribers)=>
                # finished
                logger.verbose "Unsubscribed #{totalSubscribers} subscribers from #{@name}"
                performDelete()

    log: (cb) ->
        @redis.multi()
            # account number of sent notification since event creation
            .hincrby(@key, "total", 1)
            # store last notification date for this event
            .hset(@key, "last", Math.round(new Date().getTime() / 1000))
            .exec =>
                cb() if cb

    # Performs an action on each subscriber subscribed to this event
    forEachSubscribers: (action, finished) ->
        Subscriber = require('./subscriber').Subscriber
        if (subscriber = @unicastSubscriber())?
            # if event is unicast, do not treat score as subscription option, ignore it
            action(subscriber, {}, -> finished(1) if finished)
        else
            if @name is 'broadcast'
                # if event is broadcast, do not treat score as subscription option, ignore it
                performAction = (subscriberId, subOptions) =>
                    return (doneCb) =>
                        action(new Subscriber(@redis, subscriberId), {}, (doneCb))
            else
                performAction = (subscriberId, subOptions) =>
                    options = {ignore_message: (subOptions & Event::OPTION_IGNORE_MESSAGE) isnt 0}
                    return (doneCb) =>
                        action(new Subscriber(@redis, subscriberId), options, doneCb)

            subscribersKey = if @name is 'broadcast' then 'subscribers' else "#{@key}:subs"

            perPage = 100
            page = 0

            @redis.zcard subscribersKey, (err, subcount) =>
              total = subcount
              totalPages = Math.ceil((subcount*1.0)/perPage)
              async.whilst =>
                  return  page < totalPages
              , (chunkDone) =>
                  # treat subscribers by packs of 100 with async to prevent from blocking the event loop
                  # for too long on large subscribers lists
                  @redis.zrange subscribersKey, Math.max(0,total - ((page+1)*perPage)), total - ((page)*perPage)-1, 'WITHSCORES', (err, subscriberIdsAndOptions) =>
                      tasks = []
                      for id, i in subscriberIdsAndOptions by 2
                          tasks.push performAction(id, subscriberIdsAndOptions[i + 1])
                      async.series tasks, =>
                          #total += subscriberIdsAndOptions.length / 2
                          page++
                          chunkDone()
              , =>
                  # all done
                  finished(subcount) if finished

exports.Event = Event
