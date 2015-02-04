The HTTP push protocol lets you register an arbitrary HTTP resource. Subscribed events will be posted as JSON object to the provided URL. The format of the JSON object is as follow:

``` json
{
  "event": "THE_EVENT_NAME",
  "title":
  {
    "default": "default title",
    "fr": "titre en français"
  },
  "message":
  {
    "default": "default message",
    "fr": "message en français"
  },
  "data":
  {
    "variable1": "value",
    "variable2": "value"
  }
}
```

### Token Format

An arbitrary HTTP or HTTPS URL accepting POSTs with JSON data.

### Sample Configuration

``` coffeescript
exports['http'] =
    enabled: yes
    class: require('./lib/pushservices/http').PushServiceHTTP
```

