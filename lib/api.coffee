async = require 'async'
util = require 'util'

filterFields = (params) ->
    fields = {}
    fields[key] = val for own key, val of params when key in ['proto', 'token', 'lang', 'badge', 'version']
    return fields

exports.setupRestApi = (app, createSubscriber, getEventFromId, authorize, testSubscriber) ->
    authorize ?= (realm) ->

    # subscriber registration
    app.post '/subscribers', authorize('register'), (req, res) ->
        try
            fields = filterFields(req.body)
            createSubscriber fields, (subscriber, created) ->
                subscriber.get (info) ->
                    info.id = subscriber.id
                    res.header 'Location', "/subscriber/#{subscriber.id}"
                    res.json info, if created then 201 else 200
        catch error
            res.json error: error.message, 400

    # Get subscriber info
    app.get '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
        req.subscriber.get (fields) ->
            res.json fields, if fields? then 200 else 404

    # Edit subscriber info
    app.post '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
        fields = filterFields(req.body)
        req.subscriber.set fields, (edited) ->
            res.send if edited then 204 else 404

    # Unregister subscriber
    app.delete '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
        req.subscriber.delete (deleted) ->
            res.send if deleted then 204 else 404

    app.post '/subscriber/:subscriber_id/test', authorize('register'), (req, res) ->
        testSubscriber(req.subscriber)
        res.send 201

    # Get subscriber subscriptions
    app.get '/subscriber/:subscriber_id/subscriptions', authorize('register'), (req, res) ->
        req.subscriber.getSubscriptions (subs) ->
            if subs?
                subsAndOptions = {}
                for sub in subs
                    subsAndOptions[sub.event.name] = {ignore_message: (sub.options & sub.event.OPTION_IGNORE_MESSAGE) isnt 0}
                res.json subsAndOptions
            else
                res.send 404

    # Set subscriber subscriptions
    app.post '/subscriber/:subscriber_id/subscriptions', authorize('register'), (req, res) ->
        subsToAdd = req.body
        for eventId, optionsDict of req.body
            try
                event = getEventFromId(eventId)
                options = 0
                if optionsDict? and typeof(optionsDict) is 'object' and optionsDict.ignore_message
                    options |= event.OPTION_IGNORE_MESSAGE
                subsToAdd[event.name] = event: event, options: options
            catch error
                res.json error: error.message, 400
                return

        req.subscriber.getSubscriptions (subs) ->
            tasks = []

            for sub in subs
                if sub.event.name of subsToAdd
                    subToAdd = subsToAdd[sub.event.name]
                    if subToAdd.options != sub.options
                        tasks.push ['set', subToAdd.event, subToAdd.options]
                    delete subsToAdd[sub.event.name]
                else
                    tasks.push ['del', sub.event, 0]

            for eventName, sub of subsToAdd
                tasks.push ['add', sub.event, sub.options]

            async.every tasks, (task, callback) ->
                [action, event, options] = task
                if action == 'add'
                    req.subscriber.addSubscription event, options, (added) ->
                        callback(added)
                else if action == 'del'
                    req.subscriber.removeSubscription event, (deleted) ->
                        callback(deleted)
                else if action == 'set'
                    req.subscriber.addSubscription event, options, (added) ->
                        callback(!added) # should return false
            , (result) ->
                res.send if result then 200 else 400

    # Get subscriber subscription options
    app.get '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
        req.subscriber.getSubscription req.event, (options) ->
            if options?
                res.json {ignore_message: (options & req.event.OPTION_IGNORE_MESSAGE) isnt 0}
            else
                res.send 404

    # Subscribe a subscriber to an event
    app.post '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
        options = 0
        if req.body.ignore_message
            options |= event.OPTION_IGNORE_MESSAGE
        req.subscriber.addSubscription req.event, options, (added) ->
            if added? # added is null if subscriber doesn't exist
                res.send if added then 201 else 204
            else
                res.send 404

    # Unsubscribe a subscriber from an event
    app.delete '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
        req.subscriber.removeSubscription req.event, (deleted) ->
            res.send if deleted then 204 else 404

    # Event stats
    app.get '/event/:event_id', authorize('register'), (req, res) ->
        req.event.info (info) ->
            res.json info, if info? then 200 else 404

    # Publish an event
    app.post '/event/:event_id', authorize('publish'), (req, res) ->
        res.send 204
        req.event.publish(req.body)

    # Delete an event
    app.delete '/event/:event_id', authorize('publish'), (req, res) ->
        req.event.delete (deleted) ->
            res.send if deleted 204 else 404
