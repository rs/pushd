redis = require 'redis'
subscriber = require '../lib/subscriber'
event = require '../lib/event'
pushservices = require '../lib/pushservices'


class PushServiceFake
    total: 0

    push: (subscriber, subOptions, info, payload) ->
        PushServiceFake::total++

createSubscriber = (redis, cb) ->
    info =
        proto: 'apns'
        regid: 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660'
    subscriber.createSubscriber(redis, info, cb)


exports.publish =
    setUp: (cb) ->
        @redis = redis.createClient()
        services = new pushservices.PushServices()
        services.addService('apns', new PushServiceFake())
        services.addService('c2dm', new PushServiceFake())
        services.addService('mpns', new PushServiceFake())
        @event = event.getEvent(@redis, services, 'unit-test' + Math.round(Math.random() * 100000))
        cb()

    tearDown: (cb) ->
        @event.delete =>
            if @subscriber?
                @subscriber.delete =>
                    @redis.quit()
                    cb()
            else
                @redis.quit()
                cb()

    testNoSubscriber: (test) ->
        test.expect(2)
        PushServiceFake::total = 0
        @event.publish {msg: 'test'}, (total) =>
            test.equal PushServiceFake::total, 0, 'Event with no subscriber does not push anything'
            test.equal total, 0, 'Return 0 notified subscribers'
            test.done()

    testOneSubscriber: (test) ->
        test.expect(3)
        createSubscriber @redis, (@subscriber) =>
            @subscriber.addSubscription @event, 0, (added) =>
                test.ok added is true, 'Subscription added'
                PushServiceFake::total = 0
                @event.publish {msg: 'test'}, (total) =>
                    test.equal PushServiceFake::total, 1, 'Event pushed to 1 subscriber'
                    test.equal total, 1, 'Return 1 notified subscribers'
                    test.done()

    testStats: (test) ->
        test.expect(4)
        @event.publish {msg: 'test'}, =>
            @event.info (info) =>
                test.ok info is null, 'No info on event with no subscribers'
                createSubscriber @redis, (@subscriber) =>
                    @subscriber.addSubscription @event, 0, (added) =>
                        test.ok added is true, 'Subscription added'
                        @event.publish {msg: 'test'}, =>
                            @event.info (info) =>
                                test.ok info isnt null, 'Event info returned'
                                test.equal info?.total, 1, 'Event counter incremented'
                                test.done()

    testDelete: (test) ->
        test.expect(2)
        createSubscriber @redis, (@subscriber) =>
            @subscriber.addSubscription @event, 0, (added) =>
                test.ok added is true, 'Subscription added'
                @event.delete =>
                    @subscriber.getSubscriptions (subcriptions) =>
                        test.ok subcriptions.length is 0, 'Delete event unsubscribe subscribers'
                        test.done()

