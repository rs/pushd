express = require 'express'

class TimeStatistics
    constructor: ->
        @count = 0
        @sum = 0
        @min = Infinity
        @max = 0
        
    update: (sample) ->
        @count += 1
        @sum += sample
        @min = Math.min(sample, @min)
        @max = Math.max(sample, @max)
        
    toString: -> 
        avg = @sum/@count
        "#{@count} messages received, avg: #{avg.toFixed(1)} ms (min: #{@min.toFixed(1)}, max: #{@max.toFixed(1)})"

timesPerEvent = {}

app = express()
app.use(express.bodyParser())

app.post /^\/log\/(\w+)$/, (req, res) ->
    #console.log 'Received message'
    #console.log req.body

    receivedTime = Date.now()/1000.0

    if not req.body.message?.default?
        console.log 'No default message!'
        res.send 400
        
    body = JSON.parse req.body.message.default
    if not body?.timestamp?
        console.log 'No timestamp in the body!'
        res.send 400

    event = req.body.event

    sentTime = body.timestamp
    diff = (receivedTime-sentTime)*1000
    if not timesPerEvent[event]?
        timesPerEvent[event] = new TimeStatistics()
    timesPerEvent[event].update(diff)

    console.log "#{event} " + timesPerEvent[event].toString()

    res.send 200

port = 5001
console.log "Listening on port #{port}"
app.listen port
