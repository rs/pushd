should = require 'should'
Payload = require('../lib/payload').Payload

describe 'Payload', ->
    describe 'when empty', =>
        it 'should throw an error', =>
            (=> new Payload({})).should.throw('Empty payload')
            (=> new Payload('var.test': 'value')).should.throw('Empty payload')
            (=> new Payload(sound: 'value')).should.throw('Empty payload')
            (=> new Payload(category: 'value')).should.throw('Empty payload')
            (=> new Payload(contentAvailable: 'value')).should.throw('Empty payload')

    describe 'with invalid key', =>
        it 'should throw an error', =>
            (=>new Payload(foo: 'bar')).should.throw('Invalid field: foo')

    describe 'with simple message', =>
        payload = new Payload(title: 'my title', msg: 'my message')

        it 'should fallback to default title', =>
            payload.localizedTitle('fr').should.equal 'my title'
        it 'should fallback to default message', =>
            payload.localizedMessage('fr').should.equal 'my message'

    describe 'localization', =>
        payload = new Payload
            title: 'my title'
            'title.fr': 'mon titre'
            'title.en_GB': 'my british title'
            msg: 'my message'
            'msg.fr': 'mon message'
            'msg.fr_CA': 'mon message canadien'

        it 'should fallback to default if no localization requested', =>
            payload.localizedTitle().should.equal 'my title'
        it 'should localize title in french for "fr" localization', =>
            payload.localizedTitle('fr').should.equal 'mon titre'
        it 'should localize message in french for "fr" localization', =>
            payload.localizedMessage('fr').should.equal 'mon message'
        it 'should use language if no locale found', =>
            payload.localizedTitle('fr_BE').should.equal 'mon titre'
        it 'should use full locale variant if any', =>
            payload.localizedMessage('fr_CA').should.equal 'mon message canadien'

    describe 'template', =>
        it 'should throw an error if using an undefined variable', =>
            payload = new Payload(title: 'hello ${var.name}')
            (-> payload.compile()).should.throw 'The ${var.name} does not exist'

        it 'should throw an error if using an undefined variable in localized title', =>
            payload = new Payload('title.fr': 'hello ${var.name}')
            (-> payload.compile()).should.throw 'The ${var.name} does not exist'

        it 'should throw an error with invalid variable name', =>
            payload = new Payload(title: 'hello ${name}', 'var.name': 'world')
            (-> payload.compile()).should.throw 'Invalid variable type for ${name}'

        it 'should resolve (var) variable correctly', =>
            payload = new Payload
                title: 'hello ${var.name}'
                'var.name': 'world'
            payload.localizedTitle().should.equal 'hello world'

        it 'should resolve (data) variable correctly', =>
            payload = new Payload
                title: 'hello ${data.name}'
                'data.name': 'world'
            payload.localizedTitle().should.equal 'hello world'
