http = require 'http'
url = require 'url'

class PushServiceHTTP
    validateToken: (token) ->
        info = url.parse(token)
        if info?.protocol in ['http:', 'https:']
            return token

    constructor: (@conf, @logger, tokenResolver, @failCallback) ->

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            options = url.parse(info.token)
            options.method = 'POST'
            options.headers =
              'Content-Type': 'application/json'
              'Connection': 'close'

            body =
                event: payload.event.name
                title: payload.title
                message: payload.msg
                data: payload.data

            req = http.request(options)

            req.on 'error', (e) =>
                @failCallback()
                # TODO: allow some error before removing
                #@logger?.warn("HTTP Automatic unregistration for subscriber #{subscriber.id}")
                #subscriber.delete()

            req.write(JSON.stringify(body))
            req.end()

exports.PushServiceHTTP = PushServiceHTTP
