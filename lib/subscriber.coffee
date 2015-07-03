crypto = require 'crypto'
async = require 'async'
Event = require('./event').Event
logger = require 'winston'

class Subscriber
    getInstanceFromToken: (redis, proto, token, cb) ->
        return until cb

        throw new Error("Missing redis connection") if not redis?
        throw new Error("Missing mandatory `proto' field") if not proto?
        throw new Error("Missing mandatory `token' field") if not token?

        redis.hget "tokenmap", "#{proto}:#{token}", (err, id) =>
            if id?
                # looks like this subscriber is already registered
                redis.exists "subscriber:#{id}", (err, exists) =>
                    if exists
                        cb(new Subscriber(redis, id))
                    else
                        # duh!? the global list reference an unexisting object, fix this inconsistency and return no subscriber
                        redis.hdel "tokenmap", "#{proto}:#{token}", =>
                            cb(null)
            else
                cb(null) # No subscriber for this token

    create: (redis, fields, cb, tentatives=0) ->
        return until cb

        throw new Error("Missing redis connection") if not redis?
        throw new Error("Missing mandatory `proto' field") if not fields?.proto?
        throw new Error("Missing mandatory `token' field") if not fields?.token?

        if tentatives > 10
            # exceeded the retry limit
            throw new Error "Can't find free uniq id"

        # verify if token is already registered
        Subscriber::getInstanceFromToken redis, fields.proto, fields.token, (subscriber) =>
            if subscriber?
                # this subscriber is already registered
                delete fields.token
                delete fields.proto
                subscriber.set fields, =>
                    cb(subscriber, created=false, tentatives)
            else
                # register the subscriber using a randomly generated id
                crypto.randomBytes 8, (ex, buf) =>
                    # generate a base64url random uniq id
                    id = buf.toString('base64').replace(/\=+$/, '').replace(/\//g, '_').replace(/\+/g, '-')
                    redis.watch "subscriber:#{id}", =>
                        redis.exists "subscriber:#{id}", (err, exists) =>
                            if exists
                                # already exists, rollback and retry with another id
                                redis.discard =>
                                    return Subscriber::create(redis, fields, cb, tentatives + 1)
                            else
                                fields.created = fields.updated = Math.round(new Date().getTime() / 1000)
                                redis.multi()
                                    # register subscriber token to db id
                                    .hsetnx("tokenmap", "#{fields.proto}:#{fields.token}", id)
                                    # register subscriber to global list
                                    .zadd("subscribers", 0, id)
                                    # save fields
                                    .hmset("subscriber:#{id}", fields)
                                    .exec (err, results) =>
                                        if results is null
                                            # Transction discarded due to a parallel creation of the watched subscriber key
                                            # Try again in order to get the peer created subscriber
                                            return Subscriber::create(redis, fields, cb, tentatives + 1)
                                        if not results[0]
                                            # Unlikly race condition: another client registered the same token at the same time
                                            # Rollback and retry the registration so we can return the peer subscriber id
                                            redis.del "subscriber:#{id}", =>
                                                return Subscriber::create(redis, fields, cb, tentatives + 1)
                                        else
                                            # done
                                            cb(new Subscriber(redis, id), created=true, tentatives)

    constructor: (@redis, @id) ->
        @info = null
        @key = "subscriber:#{@id}"

    delete: (cb) ->
        @redis.multi()
            # get subscriber's token
            .hmget(@key, 'proto', 'token')
            # gather subscriptions
            .zrange("subscriber:#{@id}:evts", 0, -1)
            .exec (err, results) =>
                [proto, token] = results[0]
                events = results[1]
                multi = @redis.multi()
                    # remove from subscriber token to id map
                    .hdel("tokenmap", "#{proto}:#{token}")
                    # remove from global subscriber list
                    .zrem("subscribers", @id)
                    # remove subscriber info hash
                    .del(@key)
                    # remove subscription list
                    .del("#{@key}:evts")

                # unsubscribe subscriber from all subscribed events
                for eventName in events
                    multi.zrem("event:#{eventName}:subs", @id)
                    # count subscribers after zrem
                    multi.zcard("event:#{eventName}:subs")

                multi.exec (err, results) =>
                    @info = null # flush cache
                    # check if some events have been rendered empty
                    emptyEvents = []
                    for eventName, i in events when results[4 + i + (i * 1) + 1] is 0
                        emptyEvents.push new Event(@redis, eventName)

                    async.forEach emptyEvents, ((evt, done) => evt.delete(done)), =>
                        cb(results[1] is 1) if cb # true if deleted, false if did exist

    get: (cb) ->
        return until cb
        # returned cached value or perform query
        if @info?
            cb(@info)
        else
            @redis.hgetall @key, (err, @info) =>
                if @info?.updated? # subscriber exists
                    # transform numeric value to number type
                    for own key, value of @info
                        num = parseInt(value)
                        @info[key] = if num + '' is value then num else value
                    cb(@info)
                else
                    cb(@info = null) # null if subscriber doesn't exist + flush cache

    set: (fieldsAndValues, cb) ->
        # TODO handle token update needed for Android
        throw new Error("Can't modify `token` field") if fieldsAndValues.token?
        throw new Error("Can't modify `proto` field") if fieldsAndValues.proto?
        fieldsAndValues.updated = Math.round(new Date().getTime() / 1000)
        @redis.multi()
            # check subscriber existance
            .zscore("subscribers", @id)
            # edit fields
            .hmset(@key, fieldsAndValues)
            .exec (err, results) =>
                @info = null # flush cache
                if results && results[0]? # subscriber exists?
                    cb(true) if cb
                else
                    # remove edited fields
                    @redis.del @key, =>
                        cb(null) if cb # null if subscriber doesn't exist

    incr: (field, cb) ->
        @redis.multi()
            # check subscriber existance
            .zscore("subscribers", @id)
            # increment field
            .hincrby(@key, field, 1)
            .exec (err, results) =>
                if results[0]? # subscriber exists?
                    @info[field] = results[1] if @info? # update cache field
                    cb(results[1]) if cb
                else
                    @info = null # flush cache
                    # remove edited field
                    @redis.del @key, =>
                        cb(null) if cb # null if subscriber doesn't exist

    getSubscriptions: (cb) ->
        return unless cb
        @redis.multi()
            # check subscriber existance
            .zscore("subscribers", @id)
            # gather all subscriptions
            .zrange("#{@key}:evts", 0, -1, 'WITHSCORES')
            .exec (err, results) =>
                if results[0]? # subscriber exists?
                    subscriptions = []
                    eventsWithOptions = results[1]
                    if eventsWithOptions?
                        for eventName, i in eventsWithOptions by 2
                            subscriptions.push
                                event: new Event(@redis, eventName)
                                options: parseInt(eventsWithOptions[i + 1], 10)
                    cb(subscriptions)
                else
                    cb(null) # null if subscriber doesn't exist

    getSubscription: (event, cb) ->
        return unless cb
        @redis.multi()
            # check subscriber existance
            .zscore("subscribers", @id)
            # gather all subscriptions
            .zscore("#{@key}:evts", event.name)
            .exec (err, results) =>
                if results[0]? and results[1]? # subscriber and subscription exists?
                    cb
                        event: event
                        options: parseInt(results[1], 10)
                else
                    cb(null) # null if subscriber doesn't exist

    addSubscription: (event, options, cb) ->
        @redis.multi()
            # check subscriber existance
            .zscore("subscribers", @id)
            # add event to subscriber's subscriptions list
            .zadd("#{@key}:evts", options, event.name)
            # add subscriber to event's subscribers list
            .zadd("#{event.key}:subs", options, @id)
            # set the event created field if not already there (event is lazily created on first subscription)
            .hsetnx(event.key, "created", Math.round(new Date().getTime() / 1000))
            # lazily add event to the global event list
            .sadd("events", event.name)
            .exec (err, results) =>
                if results[0]? # subscriber exists?
                    logger.verbose "Registered subscriber #{@id} to event #{event.name}"
                    cb(results[1] is 1) if cb
                else
                    # Tried to add a sub on an unexisting subscriber, remove just added sub
                    # This is an exception so we don't first check subscriber existance before to add sub,
                    # but we manually rollback the subscription in case of error
                    @redis.multi()
                        # remove the wrongly created subs subscriber relation
                        .del("#{@key}:evts", event.name)
                        # remove the subscriber from the event's subscribers list
                        .zrem("#{event.key}:subs", @id)
                        # check if the subscriber list still exist after previous zrem
                        .zcard("#{event.key}:subs")
                        .exec (err, results) =>
                            if results[2] is 0
                                # The event subscriber list is now empty, clean it
                                event.delete() # TOFIX possible race condition
                    cb(null) if cb # null if subscriber doesn't exist

    removeSubscription: (event, cb) ->
        @redis.multi()
            # check subscriber existence
            .zscore("subscribers", @id)
            # remove event from subscriber's subscriptions list
            .zrem("#{@key}:evts", event.name)
            # remove the subscriber from the event's subscribers list
            .zrem("#{event.key}:subs", @id)
            # check if the subscriber list still exist after previous zrem
            .zcard("#{event.key}:subs")
            .exec (err, results) =>
                if results[3] is 0
                    # The event subscriber list is now empty, clean it
                    event.delete() # TOFIX possible race condition

                if results[0]? # subscriber exists?
                    wasRemoved = results[1] is 1 # true if removed, false if wasn't subscribed
                    if wasRemoved
                        logger.verbose "Subscriber #{@id} unregistered from event #{event.name}"
                    cb(wasRemoved) if cb
                else
                    cb(null) if cb # null if subscriber doesn't exist


exports.Subscriber = Subscriber
