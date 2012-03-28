device = require './device'
async = require 'async'


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
        payload = new EventPayload(data)

        @redis.sismember "events", @name, (err, exists) =>
            if not exists
                cb(0) if cb
                return

            @forEachSubscribers (device, subOptions, done) =>
                # action
                @pushservices.push(device, subOptions, payload, done)
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
        @forEachSubscribers (device, subOptions, done) =>
            # action
            device.removeSubscription(@, done)
        , =>
            # finished
            @redis.multi()
                # delete event's info hash
                .del(@key)
                # remove event from global event list
                .srem("events", @name)
                .exec ->
                    cb() if cb

    # Performs an action on each device subsribed to this event
    forEachSubscribers: (action, finished) ->
        if @name is 'broadcast'
            # if event is broadcast, do not treat score as subscription option, ignore it
            performAction = (deviceId, subOptions) =>
                return (done) =>
                    action(device.getDevice(@redis, deviceId), 0, done)
        else
            performAction = (deviceId, subOptions) =>
                return (done) =>
                    action(device.getDevice(@redis, deviceId), subOptions, done)

        subscribersKey = if @name is 'boardcast' then 'devices' else "#{@key}:devs"
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
            @redis.zrange subscribersKey, (page++ * perPage), (page * perPage + perPage), 'WITHSCORES', (err, deviceIdsAndOptions) =>
                tasks = []
                for id, i in deviceIdsAndOptions by 2
                    tasks.push performAction(id, deviceIdsAndOptions[i + 1])
                async.series tasks, =>
                    total += deviceIdsAndOptions.length / 2
                    done()
        , =>
            # all done
            finished(total) if finished


class EventPayload
    locale_format: /^[a-z]{2}_[A-Z]{2}$/

    localizedMessage: (lang) ->
        if @msg[lang]?
            return @msg[lang]
        # Try with lang only in case of full locale code (en_CA)
        else if EventPayload::locale_format.test(lang) and @msg[lang[0..1]]?
            return @msg[lang[0..1]]
        else if @msg.default
            return @msg.default


    constructor: (data) ->
        throw new Error('Invalid payload') unless typeof data is 'object'

        @msg = {}
        @data = {}
        @var = {}

        # Read fields
        for own key, value of data
            if typeof value isnt 'string'
                throw new Error("Invalid value for `#{key}'")
            if key is 'msg'
                @msg.default = value
            else if key.length > 5 and key.indexOf('msg.') is 0
                @msg[key[4..-1]] = value
            else if key.length > 6 and key.indexOf('data.') is 0
                @data[key[5..-1]] = value
            else if key.length > 5 and key.indexOf('var.') is 0
                @data[key[4..-1]] = value
            else if key is 'sound'
                @sound = value
            else
                throw new Error("Invalid field: #{key}")

        # Resolve msg variables
        for own lang, msg of @msg
            msg.replace /\$\{(.*?)\}/g, (variable) ->
                [prefix, key] = variable.split('.', 2)
                if prefix not in ['var', 'data']
                    throw new Error('Invalid variable ${#{variable}}')
                if not @[prefix][key]?
                    throw new Error('The ${#{variable}} does not exist')
                return @[prefix][key]

        # Detect empty payload
        if ((lang for own lang of @msg).length + (key for own key of @data).length) == 0
            throw new Error('Empty payload')


exports.getEvent = (redis, pushservices, eventName) ->
    return new Event(redis, pushservices, eventName)
