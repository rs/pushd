should = require 'should'
async = require 'async'
Subscriber = require('../lib/subscriber').Subscriber
Event = require('../lib/event').Event
redis = require 'redis'

createSubscriber = (redisClient, proto, token, cb) ->
    info = {proto: proto, token: token}
    try
        Subscriber::create(redisClient, info, cb)
    catch e
        redisClient.quit()
        throw e

randomSubscriberToken = ->
    chars = '0123456789ABCDEF'
    token = ''
    token += chars[Math.floor(Math.random() * chars.length)] for i in [1..64]
    return token

histogram = (arr) ->
    counts = {}
    for x in arr
        counts[x] = if counts[x]? then counts[x]+1 else 1
    return counts

describe 'Subscriber', ->
    @redis = null
    @event = null
    @subscriber = null
    @testEvent = null
    @testEvent2 = null

    xdescribe = (title, fn) =>
        describe title, =>
            fn()

            before (done) =>
                @redis = redis.createClient()
                @redis.multi()
                    .select(1)
                    .exec =>
                        createSubscriber @redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (@subscriber, created, tentatives) =>
                            @subscriber.should.be.an.instanceof Subscriber
                            created.should.be.true
                            tentatives.should.equal 0
                            done()

            after (done) =>
                @subscriber.delete =>
                    @redis.keys '*', (err, keys) =>
                        keys.should.be.empty
                        done()


    xdescribe 'register twice', =>
        it 'should not create a second object', (done) =>
            createSubscriber @redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (subscriber, created, tentatives) =>
                subscriber.should.be.an.instanceof Subscriber
                created.should.be.false
                tentatives.should.equal 0
                subscriber.id.should.equal @subscriber.id
                done()

    xdescribe 'get instance from token', =>
        it 'should return the instance if already registered', (done) =>
            Subscriber::getInstanceFromToken @subscriber.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (subscriber) =>
                subscriber.should.be.an.instanceof Subscriber
                subscriber.id.should.equal @subscriber.id
                done()
        it 'should return null if not registered', (done) =>
            Subscriber::getInstanceFromToken @subscriber.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6661', (subscriber) =>
                should.not.exist subscriber
                done()

    xdescribe 'defaults', =>
        it 'should have some default values', (done) =>
            @subscriber.get (fields) =>
                should.exist fields
                fields.should.have.property 'proto'
                fields.should.have.property 'token'
                fields.should.have.property 'created'
                fields.should.have.property 'updated'
                fields.should.not.have.property 'badge'
                done()

    xdescribe 'incr()', =>
        it 'should not increment field of an unexisting subscriber', (done) =>
            subscriber = new Subscriber(@redis, 'invalidid')
            subscriber.incr 'badge', (value) =>
                should.not.exist value
                done()
        it 'should increment unexisting field to 1', (done) =>
            @subscriber.incr 'badge', (value) =>
                value.should.equal 1
                done()
        it 'should increment an existing field', (done) =>
            @subscriber.incr 'badge', (value) =>
                value.should.equal 2
                done()

    xdescribe 'set()', =>
        it 'should not edit an unexisting subscriber', (done) =>
            subscriber = new Subscriber(@subscriber.redis, 'invalidid')
            subscriber.set {lang: 'us'}, (edited) =>
                should.not.exist edited
                done()
        it 'should edit an existing subscriber', (done) =>
            @subscriber.set {lang: 'us', badge: 5}, (edited) =>
                edited.should.be.true
                @subscriber.get (fields) =>
                    should.exist fields
                    fields.lang.should.equal 'us'
                    fields.badge.should.equal 5
                    done()

    xdescribe 'delete()', =>
        it 'should delete correctly', (done) =>
            @subscriber.delete (deleted) =>
                deleted.should.be.true
                done()
        it 'should not delete an already deleted subscription', (done) =>
            @subscriber.delete (deleted) =>
                deleted.should.be.false
                done()
        it 'should no longer exist', (done) =>
            @subscriber.get (fields) =>
                should.not.exist fields
                done()

    xdescribe 'getSubscriptions()', =>
        before =>
            @testEvent = new Event(@redis, 'unit-test' +  Math.round(Math.random() * 100000))
            @testEvent2 = new Event(@redis, 'unit-test' +  Math.round(Math.random() * 100000))

        it 'should return null on unexisting subscriber', (done) =>
            subscriber = new Subscriber(@redis, 'invalidid')
            subscriber.getSubscriptions (subs) =>
                should.not.exist subs
                done()
        it 'should initially return an empty subscriptions list', (done) =>
            @subscriber.getSubscriptions (subs) =>
                should.exist subs
                subs.should.be.empty
                done()
        it 'should return a subscription once subscribed', (done) =>
            @subscriber.addSubscription @testEvent, 0, (added) =>
                added.should.be.true
                @subscriber.getSubscriptions (subs) =>
                    subs.should.have.length 1
                    subs[0].event.name.should.equal @testEvent.name
                    done()
        it 'should return the added subscription with getSubscription()', (done) =>
            @subscriber.getSubscription @testEvent, (sub) =>
                sub.should.have.property 'event'
                sub.event.should.be.an.instanceof Event
                sub.event.name.should.equal @testEvent.name
                sub.should.have.property 'options'
                sub.options.should.equal 0
                done()
        it 'should return null with getSubscription() on an unsubscribed event', (done) =>
            @subscriber.getSubscription @testEvent2, (sub) =>
                should.not.exist sub
                done()

    xdescribe 'addSubscription()', =>
        before =>
            @testEvent = new Event(@redis, 'unit-test' +  Math.round(Math.random() * 100000))

        it 'should not add subscription on unexisting subscriber', (done) =>
            subscriber = new Subscriber(@subscriber.redis, 'invalidid')
            subscriber.addSubscription @testEvent, 0, (added) =>
                should.not.exist added
                done()
        it 'should add subscription correctly', (done) =>
            @subscriber.addSubscription @testEvent, 0, (added) =>
                added.should.be.true
                done()
        it 'should not add an already subscribed event', (done) =>
            @subscriber.addSubscription @testEvent, 0, (added) =>
                added.should.be.false
                done()

    xdescribe 'removeSubscription', =>
        before =>
            @testEvent = new Event(@redis, 'unit-test' +  Math.round(Math.random() * 100000))

        after (done) =>
            @testEvent.delete ->
              done()

        it 'should not remove subscription on an unexisting subscription', (done) =>
            subscriber = new Subscriber(@subscriber.redis, 'invalidid')
            subscriber.removeSubscription @testEvent, (removed) =>
                should.not.exist removed
                done()
        it 'should not remove an unsubscribed event', (done) =>
            @subscriber.removeSubscription @testEvent, (removed) =>
                removed.should.be.false
                done()
        it 'should remove an subscribed event correctly', (done) =>
            @subscriber.addSubscription @testEvent, 0, (added) =>
                added.should.be.true
                @subscriber.removeSubscription @testEvent, (removed) =>
                    removed.should.be.true
                    done()
        it 'should not remove an already removed subscription', (done) =>
            @subscriber.removeSubscription @testEvent, (removed) =>
                removed.should.be.false
                done()
                
    xdescribe 'subscriberCount()', =>
        it 'should return the numbers of subscribers for each protocol', (doneAll) =>
            subscriberProtos = ["apns", "apns", "apns", "gcm", "gcm"]
            totalSubscribers = subscriberProtos.length
            expectedCounts = histogram(subscriberProtos)

            # one apns subscriber created at before()
            totalSubscribers += 1
            expectedCounts['apns'] += 1

            subscribers = []
            async.whilst =>
                subscriberProtos.length > 0
            , (doneCreatingSubscriber) =>
                proto = subscriberProtos.pop()
                createSubscriber @redis, proto, randomSubscriberToken(), (subscriber, created, tentatives) =>
                    subscribers.push subscriber
                    doneCreatingSubscriber()
            , =>
                Subscriber::subscriberCount @redis, (total, counts) =>
                    total.should.equal totalSubscribers
                    for proto, count of counts
                        count.should.equal expectedCounts[proto]

                    async.whilst =>
                        subscribers.length > 0
                    , (doneCleaningSubscribers) =>
                        subscribers.pop().delete =>
                            doneCleaningSubscribers()
                    , =>
                        doneAll()
