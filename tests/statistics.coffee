should = require 'should'
async = require 'async'
redis = require 'redis'
Statistics = require('../lib/statistics').Statistics

describe 'Statistics', ->
    @redis = null
    @statistics = null
    
    beforeEach (done) =>
        @redis = redis.createClient()
        @redis.multi()
            .select(1) # use another db for testing
            .flushdb()
            .exec =>
                @statistics = new Statistics(@redis)
                done()

    afterEach (done) =>
        @statistics.clearPublishedCounts () =>
            @redis.keys '*', (err, keys) =>
                @redis.quit()
                keys.should.be.empty
                @statistics = null
                done()

    describe 'publish counts', =>
        it 'should increase the published count by the given amount', (done) =>
            testProto = 'unit-test' + Math.round(Math.random() * 100000)
            @statistics.increasePublishedCount testProto, 99, () =>
                @statistics.getPublishedCounts (totalPublished, publishedCounts, totalErrors, errorCounts) =>
                    publishedCounts.should.have.property testProto
                    protoTotal = 0
                    for month, count of publishedCounts[testProto]
                        protoTotal += count
                    protoTotal.should.equal 99
                    totalPublished.should.equal 99
                    totalErrors.should.equal 0
                    
                    @statistics.increasePublishedCount testProto, 1, () =>
                        @statistics.getPublishedCounts (totalPublished, publishedCounts, totalErrors, errorCounts) =>
                            publishedCounts.should.have.property testProto
                            protoTotal = 0
                            for month, count of publishedCounts[testProto]
                                protoTotal += count
                            protoTotal.should.equal 100
                            totalPublished.should.equal 100
                            totalErrors.should.equal 0
                            done()

    describe 'publish error counts', =>
        it 'should increase the error count by the given amount', (done) =>
            testProto = 'unit-test' + Math.round(Math.random() * 100000)
            @statistics.increasePushErrorCount testProto, 99, () =>
                @statistics.getPublishedCounts (totalPublished, publishedCounts, totalErrors, errorCounts) =>
                    errorCounts.should.have.property testProto
                    protoTotal = 0
                    for month, count of errorCounts[testProto]
                        protoTotal += count
                    protoTotal.should.equal 99
                    totalErrors.should.equal 99
                    
                    @statistics.increasePushErrorCount testProto, 1, () =>
                        @statistics.getPublishedCounts (totalPublished, publishedCounts, totalErrors, errorCounts) =>
                            errorCounts.should.have.property testProto
                            protoTotal = 0
                            for month, count of errorCounts[testProto]
                                protoTotal += count
                            protoTotal.should.equal 100
                            totalErrors.should.equal 100
                            done()
