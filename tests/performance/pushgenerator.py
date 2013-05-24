#!/usr/bin/python

import time
import json
import urllib
import urllib2
import base64
import random
from multiprocessing import Process

PUSHD_SERVER = 'http://admin:admin@localhost:5000'
PUSHD_SERVER_WITHOUT_AUTH = 'http://localhost:5000'
PUSHD_AUTHORIZATION = 'Basic %s' % base64.encodestring('admin:admin')
TOKEN_HTTP = 'http://localhost:5001/log'

class RepeatingMessage:
    def __init__(self, event, messagesPerMinute):
        self.event = event
        self.messagesPerMinute = messagesPerMinute
        self.pushCount = 0

    def push(self):
        print 'Pushing message to ' + self.event
        self.pushCount += 1
        msg = self.generate_message()
        urllib.urlopen(PUSHD_SERVER + '/event/' + self.event, msg).read()

    def generate_message(self):
        return 'title=performance test&msg=%s' % self.generate_body()

    def generate_body(self):
        t = time.time()
        readable = time.strftime('%Y-%m-%d %I:%M:%S', time.localtime(t))
        message = {'timestamp': t,
                   'readable_timestamp': readable,
                   'event': self.event}
        return json.dumps(message)


class Subscriber:
    def __init__(self, token, proto):
        self.token = token
        self.proto = proto
        self.subscriberId = None
        self.registerSubscriber()

    def registerSubscriber(self):
        print 'Registering subscriber %s' % self.token
        data = 'proto=%s&token=%s&lang=fi&badge=0' % (self.proto, self.token)
        response = urllib.urlopen(PUSHD_SERVER + '/subscribers', data).read()
        parsedResponse = json.loads(response)
        if 'id' not in parsedResponse:
            raise RuntimeError('No id in the reponse')
        self.subscriberId = parsedResponse['id']

    def subscribe(self, event):
        print 'User (token %s) subscribing to %s' % (self.token, event)
        url = PUSHD_SERVER + '/subscriber/%s/subscriptions/%s' % \
            (self.subscriberId, event)
        data = 'ignore_message=0'
        urllib.urlopen(url, data).read()

    def unregister(self):
        print 'Unregistering user %s' % self.token
        url = PUSHD_SERVER_WITHOUT_AUTH + '/subscriber/%s' % self.subscriberId
        request = urllib2.Request(url, data='')
        request.add_header('Authorization', PUSHD_AUTHORIZATION)
        request.get_method = lambda: 'DELETE'
        opener = urllib2.build_opener(urllib2.HTTPHandler)
        opener.open(request).read()


def pusherProcessMain(repeatingMessage):
    try:
        while True:
            repeatingMessage.push()
            time.sleep(60./repeatingMessage.messagesPerMinute)
    except KeyboardInterrupt:
        pass

    print '%d messages pushed to %s' % \
        (repeatingMessage.pushCount, repeatingMessage.event)

def generateRandomHTTPSubscribers(event, count):
    subscribers = []
    print 'Creating %d subscribers for %s' % (count, event)
    for i in xrange(count):
        subscriber = Subscriber(randomHTTPToken(), 'http')
        subscriber.subscribe(event)
        subscribers.append(subscriber)
    return subscribers

def randomHTTPToken():
    r = ''.join([random.choice('0123456789ABCDEF') for x in xrange(10)])
    return TOKEN_HTTP + '/' + r

def startPushProcesses(targets):
    print 'Starting %d push processes' % len(targets)
    processes =  []
    for message in targets:
        p = Process(target=pusherProcessMain, args=(message,))
        p.daemon = True
        p.start()
        processes.append(p)
    print 'All processes started'
    return processes

def settings():
    # events and notification frequencies
    push_targets = [RepeatingMessage('performancetest1', 2),
                   RepeatingMessage('performancetest2', 10)]
    subscribers = [generateRandomHTTPSubscribers(push_targets[0].event, 10),
                  generateRandomHTTPSubscribers(push_targets[1].event, 5)]
    return push_targets, subscribers

def main():
    push_targets, subscribers = settings()
    
    processes = startPushProcesses(push_targets)

    try:
        while True:
            time.sleep(100)
    except KeyboardInterrupt:
        print 'Quiting...'

    for p in processes:
        p.terminate()
        p.join()

    print 'All processes joined'
        
    for subscribersForMessage in subscribers:
        for subscriber in subscribersForMessage:
            subscriber.unregister()

if __name__ == '__main__':
    main()
