### Token Format

A 64 long hexadecimal number.

### Sample Configuration

``` coffeescript
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
    #address: 'feedback.sandbox.push.apple.com'
```

Parameters are transmitted as-is to the [apn node module](https://github.com/argon/node-apn).

### Converting your APNs Certificate

After requesting the certificate from Apple, export your private key as a .p12 file and download the .cer file from the iOS Provisioning Portal.

Now, in the directory containing cert.cer and key.p12 execute the following commands to generate your .pem files:

    $ openssl x509 -in cert.cer -inform DER -outform PEM -out cert.pem
    $ openssl pkcs12 -in key.p12 -out key.pem -nodes

If you are using a development certificate you may wish to name them differently to enable fast switching between development and production. The filenames are configurable within the module options, so feel free to name them something more appropriate.
