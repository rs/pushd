### Token Format

A base64 string

### Sample Configuration

``` coffeescript
exports['gcm'] =
    enabled: yes
    class: require('./lib/pushservices/gcm').PushServiceGCM
    key: 'GCM API KEY HERE'
```
