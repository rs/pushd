### Token Format

URL starting with something like `http://db3.notify.live.net/throttledthirdparty/01.00/…`

### Sample Configuration

``` coffeescript
exports['mpns-toast'] =
    enabled: yes
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    type: 'toast'
    # Used for WP7.5+ to handle deep linking
    paramTemplate: '/Page.xaml?object=${data.object_id}'

exports['mpns-tile'] =
    enabled: yes
    class: require('./lib/pushservices/mpns').PushServiceMPNS
    type: 'tile'
    # Mapping defines where - in the payload - to get the value of each required properties
    tileMapping:
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
```

The MPNS protocol has several modes (toast and tile). If you need both modes, you'll have to setup separated "protocol" configuration for each mode (selected by `type` parameter) as above.

#### Tile Mapping

For tile type notifications, you must define a mapping for each tile's parameters. Mapping values are templates so you can reference `data` or `var` present in the event. If a mapping is not defined for a parameter or a variable referenced by the mapping for a parameter is missing from the event, the property is ignore.
