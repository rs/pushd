should = require 'should'
async = require 'async'
redis = require 'redis'
Subscriber = require('../lib/subscriber').Subscriber
Event = require('../lib/event').Event
EventPublisher = require('../lib/eventpublisher').EventPublisher
PushServices = require('../lib/pushservices').PushServices


class PushServiceFake
    total: 0
    validateToken: (token) ->
        return token

    push: (subscriber, subOptions, info, payload) ->
        PushServiceFake::total++

createSubscriber = (redis, cb) ->
    chars = '0123456789ABCDEF'
    token = ''
    token += chars[Math.floor(Math.random() * chars.length)] for i in [1..64]
    Subscriber::create(redis, {proto: 'apns', token: token}, cb)

describe 'Event', ->
    @redis = null
    @event = null
    @publisher = null
    @subscriber = null

    beforeEach (done) =>
        @redis = redis.createClient()
        @redis.multi()
            .select(1) # use another db for testing
            .flushdb()
            .exec =>
                services = new PushServices()
                services.addService('apns', new PushServiceFake())
                @publisher = new EventPublisher(services)
                @event = new Event(@redis, 'unit-test' + Math.round(Math.random() * 100000))
                done()

    afterEach (done) =>
        @event.delete =>
            if @subscriber?
                @subscriber.delete =>
                    @redis.keys '*', (err, keys) =>
                        @redis.quit()
                        keys.should.be.empty
                        @subscriber = null
                        done()
            else
                @redis.keys '*', (err, keys) =>
                    keys.should.be.empty
                    done()

    describe 'forEachSubscribers()', =>
        it 'should iterate of multiple pages of subscribers', (doneAll) =>
            totalSubscribers = 410
            subscribers = []
            async.whilst =>
                subscribers.length < totalSubscribers
            , (doneCreatingSubscriber) =>
                createSubscriber @redis, (subscriber) =>
                    subscribers.push subscriber
                    subscriber.addSubscription @event, 0, (added) =>
                        doneCreatingSubscriber()
            , =>
                subscribers.length.should.equal totalSubscribers
                unhandledSubscribers = {}
                for subscriber in subscribers
                    unhandledSubscribers[subscriber.id] = true
                @event.forEachSubscribers (subscriber, subOptions, done) =>
                    unhandledSubscribers[subscriber.id].should.be.true
                    delete unhandledSubscribers[subscriber.id]
                    done()
                , (total) =>
                    total.should.equal totalSubscribers
                    (i for i of unhandledSubscribers).length.should.equal 0
                    async.whilst =>
                        subscribers.length > 0
                    , (doneCleaningSubscribers) =>
                        subscribers.pop().delete =>
                            doneCleaningSubscribers()
                    , =>
                        doneAll()

        it 'should send a broadcast event to all subscribers', (doneAll) =>
            broadcastEvent = new Event(@redis, 'broadcast')
            totalSubscribers = 410
            subscribers = []
            async.whilst =>
                subscribers.length < totalSubscribers
            , (doneCreatingSubscriber) =>
                createSubscriber @redis, (subscriber) =>
                    subscribers.push subscriber
                    doneCreatingSubscriber()
            , =>
                subscribers.length.should.equal totalSubscribers
                unhandledSubscribers = {}
                for subscriber in subscribers
                    unhandledSubscribers[subscriber.id] = true
                broadcastEvent.forEachSubscribers (subscriber, subOptions, done) =>
                    unhandledSubscribers[subscriber.id].should.be.true
                    delete unhandledSubscribers[subscriber.id]
                    done()
                , (total) =>
                    total.should.equal totalSubscribers
                    (i for i of unhandledSubscribers).length.should.equal 0
                    async.whilst =>
                        subscribers.length > 0
                    , (doneCleaningSubscribers) =>
                        subscribers.pop().delete =>
                            doneCleaningSubscribers()
                    , =>
                        doneAll()

    describe 'publish()', =>
        it 'should not push anything if no subscribers', (done) =>
            PushServiceFake::total = 0
            @publisher.publish @event, {msg: 'test'}, (total) =>
                PushServiceFake::total.should.equal 0
                total.should.equal 0
                done()

        it 'should push to one subscriber', (done) =>
            PushServiceFake::total = 0
            createSubscriber @redis, (@subscriber) =>
                @subscriber.addSubscription @event, 0, (added) =>
                    added.should.be.true
                    PushServiceFake::total.should.equal 0
                    @publisher.publish @event, {msg: 'test'}, (total) =>
                        PushServiceFake::total.should.equal 1
                        total.should.equal 1
                        done()

        it 'should push unicast event to subscriber', (done) =>
            PushServiceFake::total = 0

            createSubscriber @redis, (@subscriber) =>
                unicastEvent = new Event(@redis, "unicast:#{@subscriber.id}")

                @publisher.publish unicastEvent, {msg: 'test'}, (total) =>
                    PushServiceFake::total.should.equal 1
                    total.should.equal 1
                    unicastEvent.delete ->
                        done()

    describe 'unicastSubscriber', =>
        it 'should provide subscriber for unicast event', (doneAll) =>
            totalSubscribers = 410
            subscribers = []
            async.whilst =>
                subscribers.length < totalSubscribers
            , (doneCreatingSubscriber) =>
                createSubscriber @redis, (subscriber) =>
                    subscribers.push subscriber
                    event = new Event(@redis, "unicast:#{subscriber.id}")
                    event.unicastSubscriber().id.should.equal subscriber.id
                    doneCreatingSubscriber()
            , =>
                async.whilst =>
                    subscribers.length > 0
                , (doneCleaningSubscribers) =>
                    subscribers.pop().delete =>
                        doneCleaningSubscribers()
                , =>
                    doneAll()

    describe 'stats', =>
        it 'should increment increment total field on new subscription', (done) =>
            @publisher.publish @event, {msg: 'test'}, =>
                @event.info (info) =>
                    should.not.exist(info)
                    createSubscriber @redis, (@subscriber) =>
                        @subscriber.addSubscription @event, 0, (added) =>
                            added.should.be.true
                            @publisher.publish @event, {msg: 'test'}, =>
                                @event.info (info) =>
                                    should.exist(info)
                                    info?.total.should.equal 1
                                    done()

    describe 'delete()', =>
        it 'should unsubscribe subscribers', (done) =>
            createSubscriber @redis, (@subscriber) =>
                @subscriber.addSubscription @event, 0, (added) =>
                    added.should.be.true
                    @event.delete =>
                        @subscriber.getSubscriptions (subcriptions) =>
                            subcriptions.should.be.empty
                            done()
