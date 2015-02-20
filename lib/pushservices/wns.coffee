wns = require 'wns'

class PushServiceWNS
    tokenFormat: /^https?:\/\/[a-zA-Z0-9-.]+\.notify\.windows\.com\/\S{0,500}$/
    validateToken: (token) ->
        if PushServiceWNS::tokenFormat.test(token)
            return token

    constructor: (@conf, @logger, tokenResolver) ->
        # TODO: tileMapping configuration for WNS
        @conf.type ?= "toast"
        if @conf.type is "tile" and not @conf.tileMapping
            throw new Error("Invalid WNS configuration: missing `tileMapping` for `tile` type")

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            note = {}
            switch @conf.type
                when "toast"
                    #TODO: this always sends "ToastText2" toast.
                    if subOptions?.ignore_message isnt true
                        sender = wns.sendToastText02
                        note.text1 = payload.localizedTitle(info.lang) or '' # prevents exception
                        note.text2 = payload.localizedMessage(info.lang)
                        if @conf.launchTemplate and info.version >= 7.5
                            try
                                launch = payload.compileTemplate(@conf.launchTemplate)
                                @logger?.silly("Launch: #{launch}")
                            catch e
                                @logger?.error("Cannot compile WNS param template: #{e}")
                                return

                when "tile"
                    #TODO
                    @logger?.error("Not implemented: tile notifications")

                when "raw"
                    sender = wns.sendRaw
                    if subOptions?.ignore_message isnt true
                        if title = payload.localizedTitle(info.lang)
                            note['title'] = title
                        if message = payload.localizedMessage(info.lang)
                            note['message'] = message
                    note[key] = value for key, value of payload.data
                    # The driver only accepts payload string in raw mode
                    note = { payload: JSON.stringify(payload.data) }

                else
                    @logger?.error("Unsupported WNS notification type: #{@conf.type}")

            if sender
                try
                    options = { client_id: @conf.client_id, client_secret: @conf.client_secret }
                    if launch?
                        options["launch"] = launch
                    @logger?.silly("WNS client URL: #{info.token}")
                    sender info.token, note, options, (error, result) =>
                        if error
                            if error.shouldDeleteChannel
                                @logger?.warn("WNS Automatic unregistration for subscriber #{subscriber.id}")
                                subscriber.delete()
                        else
                            @logger?.debug("WNS result: #{JSON.stringify result}")
                catch error
                    @logger?.error("WNS Error: #{error}")

exports.PushServiceWNS = PushServiceWNS
