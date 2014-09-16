Subscriber = require('./subscriber').Subscriber
Event = require('./event').Event
 
class Statistics
    constructor: (@redis) ->

    collectStatistics: (cb) ->
        @getPublishedCounts (totalPublished, publishedOSMonthly, totalErrors, errorsOSMonthly) =>
            Subscriber::subscriberCount @redis, (numsubscribers, subscribersPerProto) =>
                Event::eventCount @redis, (numevents) =>
                    stats =
                        totalSubscribers: numsubscribers
                        subscribers: subscribersPerProto
                        totalPublished: totalPublished
                        published: publishedOSMonthly
                        totalErrors: totalErrors
                        errors: errorsOSMonthly
                        totalEvents: numevents
                    cb(stats) if cb

    increasePublishedCount: (proto, countIncreament, cb) ->
        keyname = @publishedKeyname(proto)
        @redis.incrby(keyname, countIncreament)
        cb() if cb

    increasePushErrorCount: (proto, countIncreament, cb) ->
        keyname = @errorKeyname(proto)
        @redis.incrby(keyname, countIncreament)
        cb() if cb

    getPublishedCounts: (cb) ->
        @redis.keys @allPublishedKeyname(), (err, publishedKeys) =>
            @redis.keys @allErrorsKeyname(), (err, errorKeys) =>
                @getOSMonthlyCounts publishedKeys, (totalPublished, publishedCounts) =>
                    @getOSMonthlyCounts errorKeys, (totalErrors, errorCounts) =>
                        cb(totalPublished, publishedCounts, totalErrors, errorCounts) if cb

    getOSMonthlyCounts: (keys, cb) ->
        if keys.length == 0
            cb(0, {}) if cb
            return
        
        @redis.mget keys, (err, values) =>
            countsOSMonthly = {}
            total = 0
            keys.forEach (key, i) =>
                monthAndProto = key.split(':').slice(-2)
                month = monthAndProto[0]
                proto = monthAndProto[1]
                if not countsOSMonthly[proto]?
                    countsOSMonthly[proto] = {}
                x = parseInt values[i], 10
                countsOSMonthly[proto][month] = x
                total += x
                
            cb(total, countsOSMonthly) if cb
            
    clearPublishedCounts: (cb) ->
        @redis.keys @allPublishedKeyname(), (err, statsKeys) =>
            if statsKeys?
                @redis.del statsKeys
                
            @redis.keys @allErrorsKeyname(), (err, errorKeys) =>
                if errorKeys?
                    @redis.del errorKeys

                cb() if cb

    publishedKeyname: (proto) ->
        return 'statistics:published:' + @publishedKeynamePostfix(proto)

    allPublishedKeyname: ->
        return 'statistics:published:*'
        
    errorKeyname: (proto) ->
        return 'statistics:pusherrors:' + @publishedKeynamePostfix(proto)

    allErrorsKeyname: ->
        return 'statistics:pusherrors:*'

    publishedKeynamePostfix: (proto) ->
        today = new Date
        year = today.getUTCFullYear().toString()
        month = (today.getUTCMonth() + 1).toString()
        if month.length < 2
            month = '0' + month
        return "#{year}-#{month}:#{proto}"

exports.Statistics = Statistics
