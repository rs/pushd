exports.server =
    redis_port: process.env.REDIS_PORT
    redis_host: process.env.REDIS_HOST
    # redis_socket: '/var/run/redis/redis.sock'
    # redis_auth: 'password'
    # redis_db_number: 2
    # listen_ip: '10.0.1.2'
    tcp_port: process.env.TCP_PORT
    udp_port: process.env.UDP_PORT
    access_log: process.env.ACCESS_LOG
    acl:
        # restrict publish access to private networks
        publish: ['127.0.0.1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']
#    auth:
#        # require HTTP basic authentication, username is 'admin' and
#        # password is 'password'
#        #
#        # HTTP basic authentication overrides IP-based authentication
#        # if both acl and auth are defined.
#        admin:
#            password: 'password'
#            realms: ['register', 'publish']

exports['event-source'] =
    enabled: process.env.EVENT_SOURCE_ENABLED

exports['apns'] =
    enabled: process.env.APNS_ENABLED
    class: require('./lib/pushservices/apns').PushServiceAPNS
    # Convert cert.cer and key.p12 using:
    # $ openssl x509 -in cert.cer -inform DER -outform PEM -out apns-cert.pem
    # $ openssl pkcs12 -in key.p12 -out apns-key.pem -nodes
    cert: process.env.APNS_CERT
    key: process.env.APNS_KEY
    cacheLength: process.env.APNS_CACHE_LENGTH
    # Uncomment to set the default value for parameter.
    # This setting not overrides the value for the parameter that is set in the payload fot event request.
    # category: 'show'
    # contentAvailable: true
    # Selects data keys which are allowed to be sent with the notification
    # Keep in mind that APNS limits notification payload size to 256 bytes
    payloadFilter: ['messageFrom']
    # uncommant for dev env
    #gateway: 'gateway.sandbox.push.apple.com'
    #address: 'feedback.sandbox.push.apple.com'

# # Uncomment to use same host for prod and dev
# exports['apns-dev'] =
#     enabled: yes
#     class: require('./lib/pushservices/apns').PushServiceAPNS
#     # Your dev certificats
#     cert: 'apns-cert.pem'
#     key: 'apns-key.pem'
#     cacheLength: 100
#     gateway: 'gateway.sandbox.push.apple.com'
#	  # Uncomment to set the default value for parameter.
#     # This setting not overrides the value for the parameter that is set in the payload fot event request.
#     # category: 'show'
#     # contentAvailable: true

exports["wns-toast"] =
    enabled: process.env.WNS_TOAST_ENABLED
    client_id: process.env.WNS_TOAST_CLIENT_ID
    client_secret: process.env.WNS_TOAST_CLIENT_SECRET
    class: require('./lib/pushservices/wns').PushServiceWNS
    type: 'toast'
    # Any parameters used here must be present in each push event.
    launchTemplate: process.env.WNS_TOAST_LAUNCH_TEMPLATE

exports['gcm'] =
    enabled: process.env.GCM_ENABLED
    class: require('./lib/pushservices/gcm').PushServiceGCM
    key: process.env.GCM_KEY
    #options:
       #proxy: 'PROXY SERVER HERE'

# # Legacy Android Push Service
# exports['c2dm'] =
#     enabled: yes
#     class: require('./lib/pushservices/c2dm').PushServiceC2DM
#     # App credentials
#     user: 'app-owner@gmail.com'
#     password: 'something complicated and secret'
#     source: 'com.yourcompany.app-name'
#     # How many concurrent requests to perform
#     concurrency: 10

exports['http'] =
    enabled: process.env.HTTP_ENABLED
    class: require('./lib/pushservices/http').PushServiceHTTP

exports['mpns-toast'] =
    enabled: process.env.MPNS_TOAST_ENABLED
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    type: 'toast'
    # Used for WP7.5+ to handle deep linking
    paramTemplate: process.env.MPNS_TOAST_LAUNCH_TEMPLATE

exports['mpns-tile'] =
    enabled: process.env.MPNS_TILE_ENABLED
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    type: 'tile'
    # Mapping defines where - in the payload - to get the value of each required properties
    tileMapping:
        # Used for WP7.5+ to push to secondary tiles
        # id: "/SecondaryTile.xaml?DefaultTitle=${event.name}"
        # count: "${data.count}"
        title: "${data.title}"
        backgroundImage: "${data.background_image_url}"
        backBackgroundImage: "#005e8a"
        backTitle: "${data.back_title}"
        backContent: "${data.message}"
        # param for WP8 flip tile (sent when subscriber declare a minimum OS version of 8.0)
        smallBackgroundImage: "${data.small_background_image_url}"
        wideBackgroundImage: "${data.wide_background_image_url}"
        wideBackContent: "${data.message}"
        wideBackBackgroundImage: "#005e8a"

exports['mpns-raw'] =
    enabled: process.env.MPNS_RAW_ENABLED
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    type: 'raw'

# Transports: Console, File, Http
#
# Common options:
# level:
#   error: log errors only
#   warn: log also warnings
#   info: log status messages
#   verbose: log event and subscriber creation and deletion
#   silly: log submitted message content
#
# See https://github.com/flatiron/winston#working-with-transports for
# other transport-specific options.
exports['logging'] = [
        transport: 'Console'
        options:
            level: 'info'
    ]
