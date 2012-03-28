event = require './event'
crypto = require 'crypto'

class Device
    protocols: ['apns', 'c2dm', 'mpns']
    id_format:
        'apns': /^[0-9A-Fa-f]{64}$/
        'c2dm': /^[a-zA-Z0-9]+$/
        'mpns': /^[a-zA-Z0-9]+$/

    create: (redis, fields, cb, tentatives=0) ->
        return until cb

        throw new Error("Missing mandatory `proto' field") if not fields?.proto?
        throw new Error("Missing mandatory `regid' field") if not fields?.regid?
        throw new Error("Invalid value for `proto'") if fields.proto not in Device::protocols
        throw new Error("Invalid value for `regid'") if not Device::id_format[fields.proto].test(fields.regid)

        if tentatives > 10
            # exceeded the retry limit
            throw new Error "Can't find free uniq id"

        # verify if regid is already registered
        redis.hget "regidmap", "#{fields.proto}:#{fields.regid}", (err, id) =>
            if id?
                # looks like this device is already registered
                redis.exists "device:#{id}", (err, exists) =>
                    if exists
                        device = new Device(redis, id)
                        delete fields.regid
                        delete fields.proto
                        device.set fields, =>
                            cb(device, created=false, tentatives)
                    else
                        # duh!? the global list reference an unexisting object, fix this inconsistency and try again
                        redis.hdel "regidmap", "#{fields.proto}:#{fields.regid}", =>
                            return Device::create(redis, fields, cb, tentatives + 1)
            else
                # register the device using a randomly generated id
                crypto.randomBytes 8, (ex, buf) =>
                    # generate a base64url random uniq id
                    id = buf.toString('base64').replace(/\=+$/, '').replace(/\//g, '_').replace(/\+/g, '-')
                    redis.watch "device:#{id}", =>
                        redis.exists "device:#{id}", (err, exists) =>
                            if exists
                                # already exists, rollback and retry with another id
                                redis.discard =>
                                    return Device::create(redis, fields, cb, tentatives + 1)
                            else
                                fields.created = fields.updated = Math.round(new Date().getTime() / 1000)
                                redis.multi()
                                    # register device regid to db id
                                    .hsetnx("regidmap", "#{fields.proto}:#{fields.regid}", id)
                                    # register device to global list with protocol type stored as score
                                    .zadd("devices", @protocols.indexOf(fields.proto), id)
                                    # save fields
                                    .hmset("device:#{id}", fields)
                                    .exec (err, results) =>
                                        if results is null
                                            # Transction discarded due to a parallel creation of the watched device key
                                            # Try again in order to get the peer created device
                                            return Device::create(redis, fields, cb, tentatives + 1)
                                        if not results[0]
                                            # Unlikly race condition: another client registered the same regid at the same time
                                            # Rollback and retry the registration so we can return the peer device id
                                            redis.del "device:#{id}", =>
                                                return Device::create(redis, fields, cb, tentatives + 1)
                                        else
                                            # done
                                            cb(new Device(redis, id), created=true, tentatives)

    constructor: (@redis, @id) ->
        @key = "device:#{@id}"

    delete: (cb) ->
        @redis.multi()
            # get device's regid
            .hmget(@key, 'proto', 'regid')
            # gather subscriptions
            .zrange("device:#{@id}:subs", 0, -1)
            .exec (err, results) =>
                [proto, regid] = results[0]
                events = results[1]
                multi = @redis.multi()
                    # remove from device regid to id map
                    .hdel("regidmap", "#{proto}:#{regid}")
                    # remove from global device list
                    .zrem("devices", @id)
                    # remove device info hash
                    .del(@key)
                    # remove subscription list
                    .del("#{@key}:subs")

                # unsubscribe device from all subscribed events
                multi.zrem "event:#{eventName}:devs", @id for eventName in events

                multi.exec (err, results) ->
                    cb(results[1] is 1) if cb # true if deleted, false if did exist

    get: (cb) ->
        return until cb
        @redis.hgetall @key, (err, info) =>
            if info?.updated? # device exists
                # transform numeric value to number type
                for own key, value of info
                    num = parseInt(value)
                    info[key] = if num + '' is value then num else value
                cb(info)
            else
                cb(null) # null if device doesn't exist

    set: (fieldsAndValues, cb) ->
        # TODO handle regid update needed for Android
        throw new Error("Can't modify `regid` field") if fieldsAndValues.regid?
        throw new Error("Can't modify `proto` field") if fieldsAndValues.proto?
        fieldsAndValues.updated = Math.round(new Date().getTime() / 1000)
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # edit fields
            .hmset(@key, fieldsAndValues)
            .exec (err, results) =>
                if results[0]? # device exists?
                    cb(true) if cb
                else
                    # remove edited fields
                    @redis.del @key, =>
                        cb(null) if cb # null if device doesn't exist

    incr: (field, cb) ->
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # increment field
            .hincrby(@key, field, 1)
            .exec (err, results) =>
                if results[0]? # device exists?
                    cb(results[1]) if cb
                else
                    cb(null) if cb # null if device doesn't exist

    getSubscriptions: (cb) ->
        return unless cb
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # gather all subscriptions
            .zrange("#{@key}:subs", 0, -1, 'WITHSCORES')
            .exec (err, results) ->
                if results[0]? # device exists?
                    subs = []
                    eventsWithOptions = results[1]
                    for eventName, i in eventsWithOptions by 2
                        subs.push
                            event: event.getEvent(@redis, null, eventName)
                            options: eventsWithOptions[i + 1]
                    cb(subs)
                else
                    cb(null) # null if device doesn't exist

    getSubscription: (event, cb) ->
        return unless cb
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # gather all subscriptions
            .zscore("#{@key}:subs", event.name)
            .exec (err, results) ->
                if results[0]? and results[1]? # device and sub exists?
                    cb
                        event: event
                        options: results[1]
                else
                    cb(null) # null if device doesn't exist        

    addSubscription: (event, options, cb) ->
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # add event to device's subscriptions list
            .zadd("#{@key}:subs", options, event.name)
            # add device to event's devices list
            .zadd("#{event.key}:devs", options, @id)
            # set the event created field if not already there (event is lazily created on first subscription)
            .hsetnx(event.key, "created", Math.round(new Date().getTime() / 1000))
            # lazily add event to the global event list
            .sadd("events", event.name)
            .exec (err, results) =>
                if results[0]? # device exists?
                    cb(results[1] is 1) if cb
                else
                    # Tried to add a sub on an unexisting device, remove just added sub
                    # This is an exception so we don't first check device existance before to add sub,
                    # but we manually rollback the subscription in case of error
                    @redis.multi()
                        .del("#{@key}:subs", event.name)
                        .srem(event.key, @id)
                        .exec()
                    cb(null) if cb # null if device doesn't exist

    removeSubscription: (event, cb) ->
        @redis.multi()
            # check device existance
            .zscore("devices", @id)
            # remove event from device's subscriptions list
            .zrem("#{@key}:subs", event.name)
            # remove the device from the event's devices list
            .zrem("#{event.key}:devs", @id)
            # check if the device list still exist after previous srem
            .exists(event.key)
            .exec (err, results) =>
                if results[3] is 0
                    # The event device list is now empty, clean it
                    event.delete() # TOFIX possible race condition

                if results[0]? # device exists?
                    cb(results[1] is 1) if cb # true if removed, false if wasn't subscribed
                else
                    cb(null) if cb # null if device doesn't exist

exports.createDevice = Device::create
exports.protocols = Device::protocols

exports.getDevice = (redis, id) ->
    return new Device(redis, id)
