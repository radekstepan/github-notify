# github-notify

Send emails when new GitHub Issues are created for a repo.

## Quickstart

```bash
$ npm install github-notify
```

Edit `config.json` like so:

```json
{
    "timeout": 5,
    "github": {
        "user": "github_username",
        "repo": "github_repo",
        "authenticate": {
            "type": "oauth",
            "token": "some_oauth_token"
        }
    },
    "email": {
        "fields": {
            "from": "GitHub Notify Bot <piracy@microsoft.com>",
            "to": "Mailing list <some@domain.uk>"
        },
        "smtp": {
            "host": "smtp.gmail.com",
            "port": 465,
            "secureConnection": true,
            "auth": {
                "user": "username@gmail.com",
                "pass": "password"
            }
        },
        "template": {
            "subject": "[<%= @github.repo %>] <%= @issue.title %> (#<%= @issue.number %>)",
            "html": "<%- @issue.body + '<hr>' if @issue.body %><p><a href='<%= @issue.html_url %>'><%= @issue.html_url %></a></p>"
        }
    }
}
```

<dl>
    <dt>timeout</dt>
    <dd>How often to check for new issues (in minutes).</dd>
    <dt>github.user</dt>
    <dd>A GitHub username or organisation name.</dd>
    <dt>github.repo</dt>
    <dd>A GitHub repository.</dd>
    <dt>github.authenticate</dt>
    <dd>Not required. Follow instructions at [node-github](http://mikedeboer.github.io/node-github/#Client.prototype.authenticate).</dd>
    <dt>email.fields</dt>
    <dd>For config of these follow instructions at [Nodemailer](https://github.com/andris9/Nodemailer#e-mail-message-fields).</dd>
    <dt>email.smtp</dt>
    <dd>For config of these follow instructions at [Nodemailer](https://github.com/andris9/Nodemailer#setting-up-smtp).</dd>
    <dt>email.template</dt>
    <dd>An object with two [Eco](https://github.com/sstephenson/eco) templates for building the email. Plaintext is auto-generated from the HTML version.</dd>
</dl>

And finally start it all up (exceptions are thrown, nothing is logged, nothing is exported):

```bash
$ node index.js
```