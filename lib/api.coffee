filterFields = (params) ->
    fields = {}
    fields[key] = val for own key, val of params when key in ['proto', 'regid', 'lang', 'badge', 'version']
    return fields

exports.setupRestApi = (app, createDevice) ->
    # Device registration
    app.post '/devices', (req, res) ->
        try
            fields = filterFields(req.body)
            createDevice fields, (device, created) ->
                device.get (info) ->
                    info.id = device.id
                    res.header 'Location', "/device/#{device.id}"
                    res.json info, if created then 201 else 200
        catch error
            res.json error: error.message, 400

    # Get device info
    app.get '/device/:device_id', (req, res) ->
        req.device.get (fields) ->
            res.json fields, if fields? then 200 else 404

    # Edit device info
    app.post '/device/:device_id', (req, res) ->
        fields = filterFields(req.body)
        req.device.set fields, (edited) ->
            res.send if edited then 204 else 404

    # Unregister device
    app.delete '/device/:device_id', (req, res) ->
        req.device.delete (deleted) ->
            res.send if deleted then 204 else 404

    # Get device subscriptions
    app.get '/device/:device_id/subscriptions', (req, res) ->
        req.device.getSubscriptions (subs) ->
            if subs?
                subsAndOptions = {}
                for sub in subs
                    subsAndOptions[sub.event.name] = {ignore_message: (sub.options & sub.event.OPTION_IGNORE_MESSAGE) isnt 0}
                res.json subsAndOptions
            else
                res.send 404

    # Get device subscription options
    app.get '/device/:device_id/subscriptions/:event_id', (req, res) ->
        req.device.getSubscription req.event, (options) ->
            if options?
                res.json {ignore_message: (options & req.event.OPTION_IGNORE_MESSAGE) isnt 0}
            else
                res.send 404

    # Subscribe a device to an event
    app.post '/device/:device_id/subscriptions/:event_id', (req, res) ->
        options = 0
        if req.body.ignore_message
            options |= event.OPTION_IGNORE_MESSAGE
        req.device.addSubscription req.event, options, (added) ->
            if added? # added is null if device doesn't exist
                res.send if added then 201 else 204
            else
                res.send 404

    # Unsubscribe a device from an event
    app.delete '/device/:device_id/subscriptions/:event_id', (req, res) ->
        res.device.removeSubscription req.event, (deleted) ->
            res.send if deleted then 204 else 404

    # Event stats
    app.get '/event/:event_id', (req, res) ->
        req.event.info (info) ->
            res.json info, if info? then 200 else 404

    # Publish an event
    app.post '/event/:event_id', (req, res) ->
        res.send 204
        req.event.publish(req.body)

    # Delete an event
    app.delete '/event/:event_id', (req, res) ->
        req.event.delete (deleted) ->
            res.send if deleted 204 else 404
