Payload = require('../lib/payload').Payload

exports.testEmptyPayload = (test) ->
    test.expect(3)
    test.throws =>
        payload = new Payload({})
    , Error, 'No keys is empty'
    test.throws =>
        payload = new Payload('var.test': 'value')
    , Error, 'Only vars means empty'
    test.throws =>
        payload = new Payload(sound: 'value')
    , Error, 'Only sound means empty'
    test.done()

exports.testInvalidKeys = (test) ->
    test.expect(1)
    test.throws =>
        payload = new Payload(foo: 'bar')
    , Error, 'Invalid key'
    test.done()


exports.testSimpleMessage = (test) ->
    test.expect(2)
    payload = new Payload(title: 'my title', msg: 'my message')
    test.equal payload.localizedTitle('fr'), 'my title', 'Localized title fallback to default msg'
    test.equal payload.localizedMessage('fr'), 'my message', 'Localized message fallback to default msg'
    test.done()

exports.testLocalizedMessage = (test) ->
    test.expect(5)
    payload = new Payload
        title: 'my title'
        'title.fr': 'mon titre'
        'title.en_GB': 'my british title'
        msg: 'my message'
        'msg.fr': 'mon message'
        'msg.fr_CA': 'mon message canadien'
    test.equal payload.localizedTitle(), 'my title', 'Unlocalized fallback to default'
    test.equal payload.localizedTitle('fr'), 'mon titre', 'Localized title'
    test.equal payload.localizedMessage('fr'), 'mon message', 'Localized message'
    test.equal payload.localizedTitle('fr_BE'), 'mon titre', 'Use langauge if not locale found'
    test.equal payload.localizedMessage('fr_CA'), 'mon message canadien', 'Use full locale variant if available'
    test.done()

exports.testTemplate = (test) ->
    test.expect(5)
    payload = new Payload(title: 'hello ${var.name}')
    test.throws (=> payload.compile()), Error, 'Use undefined variable'

    payload = new Payload('title.fr': 'hello ${var.name}')
    test.throws (=> payload.compile()), Error, 'Use undefined variable in a localized title'

    payload = new Payload(title: 'hello ${name}', 'var.name': 'world')
    test.throws (=> payload.compile()), Error, 'Invalid variable name'

    payload = new Payload
        title: 'hello ${var.name}'
        'var.name': 'world'
    test.equal payload.localizedTitle(), 'hello world', 'Variable in (var) resolves correctly'

    payload = new Payload
        title: 'hello ${data.name}'
        'data.name': 'world'
    test.equal payload.localizedTitle(), 'hello world', 'Variable in (data) resolves correctly'

    test.done()
