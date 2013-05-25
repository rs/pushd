mpns = require 'mpns'

class PushServiceMPNS
    tokenFormat: /^https?:\/\/[a-zA-Z0-9-.]+\.notify\.live\.net\/\S{0,500}$/
    validateToken: (token) ->
        if PushServiceMPNS::tokenFormat.test(token)
            return token

    constructor: (@conf, @logger, tokenResolver) ->
        @conf.type ?= "toast"
        if @conf.type is "tile" and not @conf.tileMapping
            throw new Error("Invalid MPNS configuration: missing `tileMapping` for `tile` type")

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = {}
            if subOptions?.ignore_message isnt true
                switch @conf.type
                    when "toast"
                        sender = mpns.sendToast
                        note.text1 = payload.localizedTitle(info.lang)
                        note.text2 = payload.localizedMessage(info.lang)
                        if @conf.paramTemplate and info.version >= 7.5
                            try
                                note.param = payload.compileTemplate(@conf.paramTemplate)
                            catch e
                                @logger.error("Cannot compile MPNS param template: #{e}")
                                return

                    when "tile" # live tile under WP 7.5 or flip tile under WP 8.0+
                        map = @conf.tileMapping
                        properties = ["id", "title", "count", "backgroundImage", "backBackgroundImage", "backTitle", "backContent"]
                        if info.version >= 8.0
                            sender = mpns.sendFlipTile
                            properties.push(["smallBackgroundImage", "wideBackgroundImage", "wideBackContent", "wideBackBackgroundImage"]...)
                        else
                            sender = mpns.sendTile
                        for property in properties
                            if map[property]
                                try
                                    note[property] = payload.compileTemplate(map[property])
                                catch e
                                    # ignore this property

                    else
                        @logger?.error("Unsupported MPNS notification type: #{@conf.type}")

            else
                sender = mpns.sendRaw
                note[key] = value for key, value of payload.data

            if sender
                sender info.token, note, (error, result) =>
                    if error
                        if error.shouldDeleteChannel
                            @logger?.warn("MPNS Automatic unregistration for subscriber #{subscriber.id}")
                            subscriber.delete()
                        else
                            @logger?.error("MPNS Error: (#{error.statusCode}) #{error.innerError}")
                    else
                        @logger?.verbose("MPNS result: #{JSON.stringify result}")

exports.PushServiceMPNS = PushServiceMPNS

