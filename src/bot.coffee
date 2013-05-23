#!/usr/bin/env coffee
async      = require 'async'
GitHubApi  = require 'github'
nodemailer = require 'nodemailer'
marked     = require 'marked'
eco        = require 'eco'
{ _ }      = require 'underscore'

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
    unless typeof property is opts.type
        throw "Incorrect type `#{key}` in config file"

# New client.
client = new GitHubApi 'version': '3.0.0'

# Authenticate?
client.authenticate config.github.authenticate if config.github.authenticate

# SMTP transporter.
transport = nodemailer.createTransport 'SMTP', config.email.smtp

# Create a time string for now.
since = (new Date()).toISOString()

# Get details of a ticket and mail it.
mail = (issue) ->
    (cb) ->
        # Markdown translate the body of the issue if provided.
        issue.body = marked(issue.body) if issue.body

        # Render the subject and html body fields.
        fields = { 'generateTextFromHTML': true }
        for key in [ 'subject', 'html' ]
            fields[key] = eco.render config.email.template[key],
                'issue':  issue
                'github': config.github

        # Merge the fields from config onto our generated fields & send.
        transport.sendMail _.extend(fields, config.email.fields), cb

check = ->
    client.issues.repoIssues
        'user':      config.github.user
        'repo':      config.github.repo
        'state':     'open'
        'sort':      'created'
        'direction': 'asc'
        'per_page':  100 # hopefully we will never create this many tickets in a timeout
        'since':     since
    , (err, data) ->
        throw err if err

        # Update time.
        since = (new Date()).toISOString()

        # As if parallel mailer.
        async.parallel ( mail(data[key]) for key in Object.keys(data) when key isnt 'meta' ), (err) ->
            throw err if err

# Init polling.
setInterval check, config.timeout * 6e4