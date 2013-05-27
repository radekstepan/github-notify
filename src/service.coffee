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
timeago    = require 'timeago'

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

errParser = (input) ->
    if typeof input is 'object'
        if input.message
            try
                return JSON.parse(input.message).message
            catch e
                return input.message

    input

errHandler = (err) ->
    jb.save 'events',
        'text': errParser err
        'time': +new Date
        'type': 'alert'

eventHandler = (obj) ->
    obj.time = +new Date
    jb.save 'events', obj

# Say we are booting.
eventHandler 'text': 'Bot online', 'type': 'good'

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
    
    eventHandler 'text': issue.title + ' (#' + issue.number + ')', 'type': 'good'

    # Merge the fields from config onto our generated fields & send.
    transport.sendMail _.extend(fields, config.email.fields), cb

# Will be a time of the last issue we have (in int).
since = null

# State switch.
running = false

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
                since = +new Date(data[0].created_at)
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
            if (new_since = +new Date(data[0].created_at)) > since then since = new_since
            running = false # no longer running

# Init polling.
setInterval check, config.timeout * 6e4

# Expose a status page.
app = flatiron.app
app.use flatiron.plugins.http, {}

app.router.path '/', ->
    @get ->
        res = @res

        async.waterfall [ (cb) ->
            jb.find 'events', {}, { '$orderby': { 'time': -1 } }, (err, cursor, count) ->
                return cb err if err
                data = []
                while cursor.next()
                    message = cursor.object()
                    if (time = new Date message.time) # parse time
                        message.time =
                            'iso': time.toISOString()
                            'formatted': ago = timeago time
                            'today': /hour|minute/.test ago
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

app.start process.env.PORT, (err) ->
    throw err if err