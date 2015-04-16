### Token Format

URL starting with something like `http://db3.notify.microsoft.com/?token=long/random+string`


### Registeration

See [authentication guide from MSDN](https://msdn.microsoft.com/en-us/library/windows/apps/hh465407.aspx).

Open [Windows Dev Center](https://dev.windows.com), sign in. Click "Submit an app" and "App Name". Use Windows Store wizard is the right choice for Windows Phone applications. If you are registering WNS for
Windows Phone application, you have to link your (already registered under same account) Windows Phone application in the wizard, when asked.

### Sample Configuration

``` coffeescript
exports["wns-toast"] =
    enabled: yes
    client_id: 'ms-app://SID-from-developer-console'
    client_secret: 'client-secret-from-developer-console'
    class: require('./lib/pushservices/wns').PushServiceWNS
    # Currently only 'toast' and 'raw' are supported.
    type: 'toast'
    # Any parameters used here must be present in each push event.
    launchTemplate: '/MainPage.xaml?cmid=${data.cmid}'
```


The WNS protocol has several modes (toast and tile). If you need both modes, you'll have to setup separated "protocol" configuration for each mode (selected by `type` parameter) as above.

#### Tile Mapping

For tile type notifications, you must define a mapping for each tile's parameters. Mapping values are templates so you can reference `data` or `var` present in the event. If a mapping is not defined for a parameter or a variable referenced by the mapping for a parameter is missing from the event, the property is ignore.
