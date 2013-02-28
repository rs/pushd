mpns = require 'mpns'

class PushServiceMPNS
    tokenFormat: /^https?:\/\/\S{0,500}$/
    validateToken: (token) ->
        if PushServiceMPNS::tokenFormat.test(token)
            return token

    constructor: (@conf, @logger, tokenResolver) ->
        @conf.type ?= "toast"
        if @conf.type is "tile" and not @conf.tileMapping
            throw new Error("Invalid MPNS configuration: missing `tileMapping` for `tile` type")

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            if subOptions?.ignore_message isnt true
                switch @conf.type
                    when "toast"
                        note = new mpns.toast()
                        note.text1 = payload.localizedTitle(info.lang)
                        note.text2 = payload.localizedMessage(info.lang)
                        if @conf.paramTemplate and subscriber.version >= 7.5
                            try
                                note.param = payload.compileTemplate(@conf.paramTemplate)
                            catch e
                                @logger.error("Cannot compile MPNS param template: #{e}")
                                return

                    when "tile" # live tile under WP 7.5 or flip tile under WP 8.0+
                        map = @conf.tileMapping
                        properties = ["id", "title", "backgroundImage", "backBackgroundImage", "backTitle", "backContent"]
                        if subscriber.version >= 8.0
                            note = new mpns.flipTile()
                            properties.push(["smallBackgroundImage", "wideBackgroundImage", "wideBackContent", "wideBackBackgroundImage"]...)
                        else
                            note = new mpns.liveTile()
                        for property in properties
                            if map[property]
                                try
                                    note[property] = payload.compileTemplate(map[property])
                                catch e
                                    # ignore this property

                    else
                        @logger?.error("Unsupported MPNS notification type: #{@conf.type}")

            else
                note = new mpns.raw()
                note[key] = value for key, value of payload.data

            if note
                note.send info.token, (error, result) =>
                    if error
                        if error.shouldDeleteChannel
                            @logger?.warn("MPNS Automatic unregistration for subscriber #{subscriber.id}")
                            subscriber.delete()
                        else
                            @logger?.error("MPNS Error: (#{error.statusCode}) #{error.innerError}")


exports.PushServiceMPNS = PushServiceMPNS

