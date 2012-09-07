exports.server =
    tcp_port: 80
    udp_port: 80
    access_log: yes
    acl:
        # restrict publish access to private networks
        publish: ['127.0.0.1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']

exports.apns =
    enabled: yes
    class: require('./lib/pushservices/apns').PushServiceAPNS
    # Convert cert.cer and key.p12 using:
    # $ openssl x509 -in cert.cer -inform DER -outform PEM -out apns-cert.pem
    # $ openssl pkcs12 -in key.p12 -out apns-key.pem -nodes
    cert: 'apns-cert.pem'
    key: 'apns-key.pem'
    cacheLength: 100
    # uncommant for dev env
    #gateway: 'gateway.sandbox.push.apple.com'

# exports.c2dm =
#     enabled: yes
#     class: require('./lib/pushservices/c2dm').PushServiceC2DM
#     # App credentials
#     user: 'app-owner@gmail.com'
#     password: 'something complicated and secret'
#     source: 'com.yourcompany.app-name'
#     # How many concurrent requests to perform
#     concurrency: 10

exports.gcm =
    enabled: yes
    class: require('./lib/pushservices/gcm').PushServiceGCM
    key: 'GCM API KEY HERE'

exports.mpns =
    enabled: no
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    endpoint: 'http://sn1.notify.live.net/throttledthirdparty/01.00/YOUR_ENDPOINT_HERE'
