#!/usr/bin/env coffee
async      = require 'async'
GitHubApi  = require 'github'
nodemailer = require 'nodemailer'
marked     = require 'marked'
eco        = require 'eco'
{ _ }      = require 'underscore'
flatiron   = require 'flatiron'
union      = require 'union'
EJDB       = require 'ejdb'
path       = require 'path'
eco        = require 'eco'
fs         = require 'fs'
stylus     = require 'stylus'
timeago    = new require 'timeago' 
baddies    = require 'connect-baddies'

pkg = require '../package.json'

# Read the config a validate it.
config = require '../config.json'
spec   = require './config.spec.json'

for key, opts of spec then do (key, opts) ->
    property = config
    for part in key.split('.')
        # Missing?
        if !(property = property[part]) and opts.required
            throw "Missing property `#{key}` in config file"

    # Correct type?
    if property and typeof property isnt opts.type
        throw "Incorrect type `#{key}` in config file"

# Replace config with env variables.
(replace = (obj) ->
    for key, value of obj
        switch
            # Replace strings...
            when _.isString value
                # ...that start with a `$` sign.
                continue unless value[0] is '$'
                # Make the replacement if we are defined.
                obj[key] = value if value = process.env[value[1...]]

            # Nested.
            when _.isObject value
                replace value
) config

# Root dir.
dir = path.resolve __dirname, '../'

# Open db.
jb = EJDB.open dir + '/db/notify.ejdb'

# New client.
client = new GitHubApi 'version': '3.0.0'

# Authenticate?
client.authenticate config.github.authenticate if config.github.authenticate

# SMTP transporter.
transport = nodemailer.createTransport 'SMTP', config.email.smtp

# Will be a time of the last issue we have (in int).
since = null

# State switch.
running = false

errParser = (input) ->
    if typeof input is 'object'
        if input.message
            try
                return JSON.parse(input.message).message
            catch e
                return input.message

    input

errHandler = (err, type='alert') ->
    jb.save 'events',
        'text': errParser err
        'time': + new Date
        'type': type

    if type is 'alert' then running = false

eventHandler = (obj) ->
    obj.time = + new Date
    jb.save 'events', obj

# Say we are booting.
eventHandler 'text': "Bot v#{pkg.version} online", 'type': 'good'

# Maybe send an email with new issue details.
mail = (issue, cb) ->
    # Is this issue actually new?
    return cb null unless +new Date(issue.created_at) > since

    # Markdown translate the body of the issue if provided.
    issue.body = marked(issue.body) if issue.body

    # Render the subject and html body fields.
    fields = { 'generateTextFromHTML': true }
    for key in [ 'subject', 'html' ]
        fields[key] = eco.render config.email.template[key],
            'issue':  issue
            'github': config.github

    eventHandler
        'text': "@#{issue.user.login}: #{issue.title} (##{issue.number})"
        'type': 'good'
        'url': issue.html_url

    # Merge the fields from config onto our generated fields & send.
    transport.sendMail _.extend(fields, config.email.fields), (err) ->
        # Although not ideal, do not die on the batch if email errors.
        if err then errHandler err, 'warn'
        cb null

do check = ->
    return if running # are we running?
    running = true    # now we are

    # Run the query.
    client.issues.repoIssues
        'user':      config.github.user
        'repo':      config.github.repo
        'state':     'open'
        'sort':      'created'
        'direction': 'desc'
        'per_page':  100 # hopefully we will never create this many tickets in an interval
    , (err, data) ->
        return errHandler err if err

        # Any tickets at all?
        if data.length isnt 0
            unless since
                # First time do not show issues we know about already.
                since = + new Date(data[0].created_at)
                return running = false

        else
            # Fetch and show everything next time.
            unless since then since = 1
            # Wait for next time then.
            return running = false

        # Run in order.
        async.eachSeries data, mail, (err) ->
            return errHandler err if err
            # Update the since time to the last created_at?
            if (new_since = + new Date(data[0].created_at)) > since then since = new_since
            running = false # no longer running

# Init polling.
interval = setInterval check, config.timeout * 6e4

# Make a response, don't care when done.
respond = (res, week) ->
    # Global access.
    previous = next = null

    # Today is what?
    today = + new Date

    # ms in a week.
    wk = 6048e5
    # Padding when getting messages form a db.
    pa = 864e5

    dateString = (int) ->
        return null unless int
        (new Date(int)).toISOString()[0...10]

    # Parse the dates.
    async.waterfall [ (cb) ->
        # When did the requested week start?
        unless week
            # This is the previous week's end.
            previous = today - wk
            # All good.
            return cb null
        else
            # Does it parse?
            if date = + new Date(week)
                # Is it in the future?
                return cb 'Time travel is not currently possible' if date > today
                # Calculate previous & next then.
                previous = date - wk ; next = date + wk
                # Would the next date be beyond today?
                next = null if next > today
                # And today is this date :).
                today = date
                # All good.
                return cb null

        cb 'Do not understand this week ending'

    # Get the data.
    , (cb) ->
        jb.find 'events', {
            # Get this particular time segment (apply padding).
            'time':
                '$gt': previous - pa
                '$lt': today + pa
        }, {
            '$orderby':
                'time': -1
        }, (err, cursor, count) ->
            return cb err if err
            data = []
            while cursor.next()
                message = cursor.object()
                if (time = new Date message.time) # parse time
                    message.time =
                        'iso': time.toISOString()
                        'formatted': ago = timeago.format time
                        'today': /hour|minute/i.test ago
                data.push message

            cb null, data

    , (messages, cb) ->
        files = {}

        l = (file) ->
            (cb) ->
                fs.readFile dir + '/src/status/' + file, (err, data) ->
                    return cb err if err
                    files[file] = data
                    cb null

        # Load all the files.
        async.parallel [ l('template.eco'), l('style.styl'), l('logo.png') ], (err, results) ->
            return cb err if err

            # Stylus.
            async.waterfall [ (cb) ->
                stylus(new String(files['style.styl']))
                .set('compress', true)
                .render cb

            # Eco render.
            , (style, cb) ->
                try
                    html = eco.render new String(files['template.eco']),
                        'messages': messages
                        # Convert ints into nice strings for paginator.
                        'paginator':
                            'previous': dateString previous
                            'today': dateString(today) if week # only show on week pages
                            'next': dateString next
                        'style': style
                        'config': config
                        'logo': new Buffer(files['logo.png']).toString('base64')
                    cb null, html
                catch e
                    cb e
            
            ], cb

    , (html, cb) ->
        res.writeHead 200, 'content-type': 'text/html'
        res.write html
        res.end()

    ], (err) ->
        if err
            res.writeHead 500, 'content-type': 'application/json'
            res.write JSON.stringify { 'error': errParser(err) }
            res.end()

# Expose a status page.
app = flatiron.app
app.use flatiron.plugins.http,
    'before': [ baddies() ]

# Root.
app.router.path '/', ->
    @get -> respond @res

# Specific week.
app.router.path '/messages/:week', ->
    @get (week) -> respond @res, week

# On close.
process.on 'SIGINT', ->
    # Stop the timeout.
    clearInterval interval
    # Kill the server.
    process.nextTick app.server.close
    # If we are lingering.
    setTimeout process.exit, 1000

# Startup.
app.start process.env.PORT, (err) ->
    throw err if err