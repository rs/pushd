mpns = require 'mpns'

class PushServiceMPNS
    tokenFormat: /^[a-zA-Z0-9_-]+$/
    validateToken: (token) ->
        if PushServiceMPNS::tokenFormat.test(token)
            return token

    constructor: (@conf, @logger) ->

    push: (subscriber, subOptions, payload) ->
        # TO BE IMPLEMENTED

exports.PushServiceMPNS = PushServiceMPNS

