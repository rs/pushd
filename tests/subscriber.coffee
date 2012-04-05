subscriber = require '../lib/subscriber'
event = require '../lib/event'
redis = require 'redis'

createSubscriber = (proto, token, cb) ->
    info = {proto: proto, token: token}
    redisClient = redis.createClient()
    try
        subscriber.createSubscriber redisClient, info, cb
    catch e
        redisClient.quit()
        throw e


exports.testCreateSubscriber = (test) ->
    test.expect(2)
    createSubscriber 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (newSubscriber) =>
        test.ok newSubscriber isnt null, 'Subscriber created'
        test.ok newSubscriber.id isnt null, 'Subscriber has id'
        newSubscriber.delete =>
            newSubscriber.redis.quit()
            test.done()

exports.subscriber =
    setUp: (cb) ->
        createSubscriber 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (@subscriber, @created, @tentatives) =>
            cb()

    tearDown: (cb) ->
        @subscriber.delete =>
            @subscriber.redis.quit()
            cb()

    testReregister: (test) ->
        test.expect(6)
        test.ok @created, 'Subscriber has been newly created'
        test.equal @tentatives, 0, 'Subscriber created with not retry'
        createSubscriber 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (newSubscriber, created, tentatives) =>
            test.ok created is false, 'Second subscriber not newly created'
            test.equal @tentatives, 0, 'Second subscriber created with not retry'
            test.ok newSubscriber isnt null, 'The subscriber have been created'
            test.equal newSubscriber?.id, @subscriber.id, 'Got the same subscriber if re-register same token'
            newSubscriber?.redis?.quit()
            test.done()

    testGetInstanceFromtoken: (test) ->
        test.expect(4)
        test.ok @created, 'Subscriber has been newly created'
        test.equal @tentatives, 0, 'Subscriber created with not retry'
        subscriber.getSubscriberFromToken @subscriber.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (sub) =>
            test.equal sub?.id, @subscriber.id, 'Get instance from getid get the same subscriber'
            subscriber.getSubscriberFromToken @subscriber.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6661', (sub) =>
                test.ok sub is null, 'Get instance on unregistered token returns null'
                test.done()


    testDefaults: (test) ->
        test.expect(7)
        test.equal @tentatives, 0, 'Subscriber created with not retry'
        @subscriber.get (fields) =>
            test.notEqual fields, null, 'Returned fields are not null'
            test.ok fields?.proto?, 'The proto field is present'
            test.ok fields?.token?, 'The token field is present'
            test.ok fields?.created?, 'The created field is present'
            test.ok fields?.updated?, 'The updated field is present'
            test.ok not fields?.badge?, 'Unexisting field is not present'
            test.done()

    testIncrement: (test) ->
        test.expect(4)
        test.equal @tentatives, 0, 'Subscriber created with not retry'
        subscriber.getSubscriber(@subscriber.redis, 'invalidid').incr 'badge', (value) =>
            test.ok value is null, 'Cannot increment field of an unexisting subscriber'
            @subscriber.incr 'badge', (value) =>
                test.equal value, 1, 'Increment unexisting field starts at 1'
                @subscriber.incr 'badge', (value) =>
                    test.equal value, 2, 'Exsiting value is correctly incremented'
                    test.done()

    testSet: (test) ->
        test.expect(5)
        test.equal @tentatives, 0, 'Subscriber created with not retry'
        subscriber.getSubscriber(@subscriber.redis, 'invalidid').set {lang: 'us'}, (edited) =>
            test.ok edited is null, 'Cannot edit an unexisting subscriber'
            @subscriber.set {lang: 'us', badge: 5}, (edited) =>
                test.ok edited, 'Edit return true'
                @subscriber.get (fields) =>
                    test.equal fields?.lang, 'us', 'Lang edited correctly'
                    test.equal fields?.badge, 5, 'Badge edited correctly'
                    test.done()

    testDelete: (test) ->
        test.expect(4)
        test.equal @tentatives, 0, 'subscriber created with not retry'
        @subscriber.delete (deleted) =>
            test.ok deleted is true, 'Correctly deleted'
            @subscriber.delete (deleted) =>
                test.ok deleted is false, 'Already deleted'
                @subscriber.get (fields) =>
                    test.equal fields, null, 'No longer exists'
                    test.done()

    testGetSubscription: (test) ->
        test.expect(9)
        testEvent = event.getEvent(@subscriber.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        testEvent2 = event.getEvent(@subscriber.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'subscriber created with not retry'
        subscriber.getSubscriber(@subscriber.redis, 'invalidid').getSubscriptions (subs) =>
            test.ok subs is null, 'Cannot get subscriptions on unexisting subscriber'
            @subscriber.getSubscriptions (subs) =>
                test.equal subs.length, 0, 'Initially no subscriptions'
                @subscriber.addSubscription testEvent, 0, (added) =>
                    test.ok added is true, '1 subscription added'
                    @subscriber.getSubscriptions (subs) =>
                        test.equal subs.length, 1, '1 subscription retrieved'
                        test.equal subs[0].event.name, testEvent.name, 'The added event is returned'
                        @subscriber.getSubscription testEvent, (sub) =>
                            test.equal sub?.event.name, testEvent.name, 'The subscription returns event'
                            test.equal sub?.options, 0, 'The subscription returns options'
                            @subscriber.getSubscription testEvent2, (sub) =>
                                test.ok sub is null, 'The subscription does not exists'
                                test.done()

    testAddSubscription: (test) ->
        test.expect(4)
        testEvent = event.getEvent(@subscriber.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'subscriber created with not retry'
        subscriber.getSubscriber(@subscriber.redis, 'invalidid').addSubscription testEvent, 0, (added) =>
            test.ok added is null, 'Cannot add subscription on unexisting subscriber'
            @subscriber.addSubscription testEvent, 0, (added) =>
                test.ok added is true, 'Added'
                @subscriber.addSubscription testEvent, 0, (added) =>
                    test.ok added is false, 'Already added'
                    test.done()

    testRemoveSubscription: (test) ->
        test.expect(6)
        testEvent = event.getEvent(@subscriber.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'subscriber created with not retry'
        subscriber.getSubscriber(@subscriber.redis, 'invalidid').removeSubscription testEvent, (removed) =>
            test.ok removed is null, 'Cannot remove subscription on unexisting subscriber'
            @subscriber.removeSubscription testEvent, (removed) =>
                test.ok removed is false, 'Remove unexisting subscription'
                @subscriber.addSubscription testEvent, 0, (added) =>
                    test.ok added is true, 'Subscription added'
                    @subscriber.removeSubscription testEvent, (removed) =>
                        test.ok removed is true, 'Subscription removed'
                        @subscriber.removeSubscription testEvent, (removed) =>
                            test.ok removed is false, 'Subscription already removed'
                            test.done()