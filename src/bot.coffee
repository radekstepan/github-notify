#!/usr/bin/env coffee
async      = require 'async'
GitHubApi  = require 'github'
nodemailer = require 'nodemailer'
marked     = require 'marked'
eco        = require 'eco'
{ _ }      = require 'underscore'
flatiron   = require 'flatiron'
union      = require 'union'
winston    = require 'winston'

winston.cli()

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

# New client.
client = new GitHubApi 'version': '3.0.0'

# Authenticate?
client.authenticate config.github.authenticate if config.github.authenticate

# SMTP transporter.
transport = nodemailer.createTransport 'SMTP', config.email.smtp

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

    winston.data "#{issue.title.bold} (##{issue.number}) created `#{issue.created_at}`"

    return cb null

    # Merge the fields from config onto our generated fields & send.
    transport.sendMail _.extend(fields, config.email.fields), cb

# Will be a time of the last issue we have (in int).
since = null

# State switch.
running = false

do check = ->
    return if running # are we running?
    running = true    # now we are
    winston.info 'Running a check on ' + (config.github.user + '/' + config.github.repo).bold

    # Run the query.
    client.issues.repoIssues
        'user':      config.github.user
        'repo':      config.github.repo
        'state':     'open'
        'sort':      'created'
        'direction': 'desc'
        'per_page':  100 # hopefully we will never create this many tickets in an interval
    , (err, data) ->
        throw err if err

        # Any tickets at all?
        if data.length isnt 0
            unless since
                # First time do not show issues we know about already.
                since = +new Date(data[0].created_at)
                winston.help "First time, skipping since `#{data[0].created_at}`"
                return running = false

        else
            winston.help 'Nothing new'
            # Fetch and show everything next time.
            unless since then since = 1
            # Wait for next time then.
            return running = false

        # Run in order.
        winston.help 'New issues may have been created'
        async.eachSeries data, mail, (err) ->
            throw err if err
            since = +new Date(data[0].created_at) # update the since time to the last created_at
            running = false # no longer running

# Init polling.
setInterval check, config.timeout * 6e4

# Expose a minimal service.
app = flatiron.app
app.use flatiron.plugins.http, {}

# Create a 'safe' version of the config.
safe_config = JSON.parse JSON.stringify config
delete safe_config.github.authenticate
delete safe_config.email.smtp

app.router.path '/', ->
    @get ->
        @res.writeHead 200, 'content-type': 'application/json'
        @res.write JSON.stringify safe_config
        @res.end()

app.start process.env.PORT, (err) ->
    throw err if err