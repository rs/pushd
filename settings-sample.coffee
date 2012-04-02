exports.apns =
    # Convert cert.cer and key.p12 using:
    # $ openssl x509 -in cert.cer -inform DER -outform PEM -out apns-cert.pem
    # $ openssl pkcs12 -in key.p12 -out apns-key.pem -nodes
    cert: 'apns-cert.pem'
    key: 'apns-key.pem'
    cacheLength: 100
    # uncommant for dev env
    #gateway: 'gateway.sandbox.push.apple.com'

exports.c2dm =
    # Obtained with curl -X POST https://www.google.com/accounts/ClientLogin -d Email=ROLE_EMAIL -d Passwd=ROLE_PASSWORDPASS -d accountType=HOSTED_OR_GOOGLE -d service=ac2dm -d source=YOURCOMPANY-YOURAPP-Version
    token: 'Auth=VVVVEEERY-HUDE-TOKEN'
    # How many concurrent requests to perform
    concurrency: 10

exports.mpns =
    endpoint: 'http://sn1.notify.live.net/throttledthirdparty/01.00/YOUR_ENDPOINT_HERE'
