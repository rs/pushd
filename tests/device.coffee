device = require '../lib/device'
event = require '../lib/event'
redis = require 'redis'

createDevice = (proto, regid, cb) ->
    info = {proto: proto, regid: regid}
    redisClient = redis.createClient()
    try
        device.createDevice redisClient, info, cb
    catch e
        redisClient.quit()
        throw e


exports.testCreateDevice = (test) ->
    test.expect(2)
    createDevice 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (newDevice) =>
        test.ok newDevice isnt null, 'Device created'
        test.ok newDevice.id isnt null, 'Device has id'
        newDevice.delete =>
            newDevice.redis.quit()
            test.done()

exports.testCreateDeviceWithInvalidRegid = (test) ->
    test.expect(2)
    regids =
    [
        'FE66489F304DC75B8D6E8200DFF8A4 56E8DAEACEC428B427E9518741C92C6660'
        'invalid$'
    ]
    for regid in regids
        test.throws =>
            createDevice 'apns', regid, =>
        , Error, "Cannot create device with invalid regid: #{regid}"
    test.done()


exports.device =
    setUp: (cb) ->
        createDevice 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (@device, @created, @tentatives) =>
            cb()

    tearDown: (cb) ->
        @device.delete =>
            @device.redis.quit()
            cb()

    testReregister: (test) ->
        test.expect(6)
        test.ok @created, 'Device has been newly created'
        test.equal @tentatives, 0, 'Device created with not retry'
        createDevice 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (newDevice, created, tentatives) =>
            test.ok created is false, 'Second device not newly created'
            test.equal @tentatives, 0, 'Second device created with not retry'
            test.ok newDevice isnt null, 'The device have been created'
            test.equal newDevice?.id, @device.id, 'Got the same device if re-register same regid'
            newDevice?.redis?.quit()
            test.done()

    testGetInstanceFromRegId: (test) ->
        test.expect(5)
        test.ok @created, 'Device has been newly created'
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDeviceFromRegId @device.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6660', (dev) =>
            test.equal dev.id, @device.id, 'Get instance from getid get the same device'
            device.getDeviceFromRegId @device.redis, 'apns', 'fe66489f304dc75b8d6e8200dff8a456e8daeacec428b427e9518741c92c6660', (dev) =>
                test.equal dev.id, @device.id, 'Get instance from getid with different case get the same device'
                device.getDeviceFromRegId @device.redis, 'apns', 'FE66489F304DC75B8D6E8200DFF8A456E8DAEACEC428B427E9518741C92C6661', (dev) =>
                    test.ok dev is null, 'Get instance on unregistered regid returns null'
                    test.done()


    testDefaults: (test) ->
        test.expect(7)
        test.equal @tentatives, 0, 'Device created with not retry'
        @device.get (fields) =>
            test.notEqual fields, null, 'Returned fields are not null'
            test.ok fields?.proto?, 'The proto field is present'
            test.ok fields?.regid?, 'The regid field is present'
            test.ok fields?.created?, 'The created field is present'
            test.ok fields?.updated?, 'The updated field is present'
            test.ok not fields?.badge?, 'Unexisting field is not present'
            test.done()

    testIncrement: (test) ->
        test.expect(4)
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDevice(@device.redis, 'invalidid').incr 'badge', (value) =>
            test.ok value is null, 'Cannot increment field of an unexisting device'
            @device.incr 'badge', (value) =>
                test.equal value, 1, 'Increment unexisting field starts at 1'
                @device.incr 'badge', (value) =>
                    test.equal value, 2, 'Exsiting value is correctly incremented'
                    test.done()

    testSet: (test) ->
        test.expect(5)
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDevice(@device.redis, 'invalidid').set {lang: 'us'}, (edited) =>
            test.ok edited is null, 'Cannot edit an unexisting device'
            @device.set {lang: 'us', badge: 5}, (edited) =>
                test.ok edited, 'Edit return true'
                @device.get (fields) =>
                    test.equal fields?.lang, 'us', 'Lang edited correctly'
                    test.equal fields?.badge, 5, 'Badge edited correctly'
                    test.done()

    testDelete: (test) ->
        test.expect(4)
        test.equal @tentatives, 0, 'Device created with not retry'
        @device.delete (deleted) =>
            test.ok deleted is true, 'Correctly deleted'
            @device.delete (deleted) =>
                test.ok deleted is false, 'Already deleted'
                @device.get (fields) =>
                    test.equal fields, null, 'No longer exists'
                    test.done()

    testGetSubscription: (test) ->
        test.expect(9)
        testEvent = event.getEvent(@device.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        testEvent2 = event.getEvent(@device.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDevice(@device.redis, 'invalidid').getSubscriptions (subs) =>
            test.ok subs is null, 'Cannot get subscriptions on unexisting device'
            @device.getSubscriptions (subs) =>
                test.equal subs.length, 0, 'Initially no subscriptions'
                @device.addSubscription testEvent, 0, (added) =>
                    test.ok added is true, '1 subscription added'
                    @device.getSubscriptions (subs) =>
                        test.equal subs.length, 1, '1 subscription retrieved'
                        test.equal subs[0].event.name, testEvent.name, 'The added event is returned'
                        @device.getSubscription testEvent, (sub) =>
                            test.equal sub?.event.name, testEvent.name, 'The subscription returns event'
                            test.equal sub?.options, 0, 'The subscription returns options'
                            @device.getSubscription testEvent2, (sub) =>
                                test.ok sub is null, 'The subscription does not exists'
                                test.done()

    testAddSubscription: (test) ->
        test.expect(4)
        testEvent = event.getEvent(@redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDevice(@device.redis, 'invalidid').addSubscription testEvent, 0, (added) =>
            test.ok added is null, 'Cannot add subscription on unexisting device'
            @device.addSubscription testEvent, 0, (added) =>
                test.ok added is true, 'Added'
                @device.addSubscription testEvent, 0, (added) =>
                    test.ok added is false, 'Already added'
                    test.done()

    testRemoveSubscription: (test) ->
        test.expect(6)
        testEvent = event.getEvent(@device.redis, null, 'unit-test' +  Math.round(Math.random() * 100000))
        test.equal @tentatives, 0, 'Device created with not retry'
        device.getDevice(@device.redis, 'invalidid').removeSubscription testEvent, (removed) =>
            test.ok removed is null, 'Cannot remove subscription on unexisting device'
            @device.removeSubscription testEvent, (removed) =>
                test.ok removed is false, 'Remove unexisting subscription'
                @device.addSubscription testEvent, 0, (added) =>
                    test.ok added is true, 'Subscription added'
                    @device.removeSubscription testEvent, (removed) =>
                        test.ok removed is true, 'Subscription removed'
                        @device.removeSubscription testEvent, (removed) =>
                            test.ok removed is false, 'Subscription already removed'
                            test.done()