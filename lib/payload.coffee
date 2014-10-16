serial = 0

class Payload
    locale_format: /^[a-z]{2}_[A-Z]{2}$/

    constructor: (data) ->
        throw new Error('Invalid payload') unless typeof data is 'object'

        @id = serial++
        @compiled = no
        @title = {}
        @msg = {}
        @data = {}
        @var = {}
        @incrementBadge = yes

        # Read fields
        for own key, value of data
            if typeof key isnt 'string' or key.length == 0
                throw new Error("Invalid field (empty)")
            if typeof value isnt 'string'
                throw new Error("Invalid value for `#{key}'")

            switch key
                when 'title' then @title.default = value
                when 'msg' then @msg.default = value
                when 'sound' then @sound = value
                when 'incrementBadge' then @incrementBadge = value != 'false'
                when 'category' then @category = value
                when 'contentAvailable' then @contentAvailable = value != 'false'
                else
                    if ([prefix, subkey] = key.split('.', 2)).length is 2
                        @[prefix][subkey] = value
                    else
                        throw new Error("Invalid field: #{key}")

        # Detect empty payload
        sum = 0
        sum += (key for own key of @[type]).length for type in ['title', 'msg', 'data']
        if sum is 0 then throw new Error('Empty payload')

    localizedTitle: (lang) ->
        @localized('title', lang)

    localizedMessage: (lang) ->
        @localized('msg', lang)

    localized: (type, lang) ->
        @compile() unless @compiled
        if @[type][lang]?
            return @[type][lang]
        # Try with lang only in case of full locale code (en_CA)
        else if Payload::locale_format.test(lang) and @[type][lang[0..1]]?
            return @[type][lang[0..1]]
        else if @[type].default
            return @[type].default

    compile: ->
        # Compile title and msg templates
        @[type][lang] = @compileTemplate(msg) for own lang, msg of @[type] for type in ['title', 'msg']
        @compiled = yes

    compileTemplate: (tmpl) ->
        return tmpl.replace /\$\{(.*?)\}/g, (match, keyPath) =>
            return @.variable(keyPath)

    # Extracts variable from payload. The keyPath can be `var.somekey` or `data.somekey`
    variable: (keyPath) ->
        if keyPath is 'event.name'
            # Special case
            if @event?.name
                return @event?.name
            else
                throw new Error("The ${#{keyPath}} does not exist")

        [prefix, key] = keyPath.split('.', 2)
        if prefix not in ['var', 'data']
            throw new Error("Invalid variable type for ${#{keyPath}}")
        if not @[prefix][key]?
            throw new Error("The ${#{keyPath}} does not exist")
        return @[prefix][key]


exports.Payload = Payload
