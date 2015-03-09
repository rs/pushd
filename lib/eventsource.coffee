policyFile = '<?xml version="1.0"?>' +
             '<!DOCTYPE cross-domain-policy SYSTEM "http://www.macromedia.com/xml/dtds/cross-domain-policy.dtd">' +
             '<cross-domain-policy>' +
             '<site-control permitted-cross-domain-policies="master-only"/>' +
             '<allow-access-from domain="*" secure="false"/>' +
             '<allow-http-request-headers-from domain="*" headers="Accept"/>' +
             '</cross-domain-policy>'

exports.setup = (app, authorize, eventPublisher) ->
    # In order to support access from flash apps
    app.get '/crossdomain.xml', (req, res) ->
        res.set 'Content-Type', 'application/xml'
        res.send(policyFile)

    app.options '/subscribe', authorize('listen'), (req, res) ->
        res.set
            'Content-Type': 'text/event-stream',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET'
            'Access-Control-Max-Age': '86400'
        res.end()

    app.get '/subscribe', authorize('listen'), (req, res) ->
        unless req.accepts('text/event-stream')
            res.send 406
            return

        unless typeof req.query.events is 'string'
            res.send 400
            return

        eventNames = req.query.events.split ' '

		# Node.js 0.12 requires timeout argument be finite
        req.socket.setTimeout(0x7FFFFFFF);
        req.socket.setNoDelay(true);
        res.set
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Access-Control-Allow-Origin': '*',
            'Connection': 'close'
        res.write('\n')

        if req.get('User-Agent')?.indexOf('MSIE') != -1
            # Work around MSIE bug preventing Progress handler from behing thrown before first 2048 bytes
            # See http://forums.adobe.com/message/478731
            res.write new Array(2048).join('\n')

        sendEvent = (event, payload) ->
            data =
                event: event.name
                title: payload.title
                message: payload.msg
                data: payload.data

            res.write("data: " + JSON.stringify(data) + "\n\n")

        antiIdleInterval = setInterval ->
            res.write "\n"
        , 10000

        res.socket.on 'close', =>
            clearInterval antiIdleInterval
            for eventName in eventNames
                eventPublisher.removeListener eventName, sendEvent

        for eventName in eventNames
            eventPublisher.addListener eventName, sendEvent
