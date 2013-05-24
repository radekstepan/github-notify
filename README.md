# github-notify

Send emails when new GitHub Issues are created for a repo.

## Quickstart

```bash
$ npm install github-notify
```

Edit the `config.json` file:

##### timeout
How often to check for new issues (in minutes).

##### github.user
A GitHub username or organisation name.

##### github.repo
A GitHub repository.

##### github.authenticate
Not required. Follow instructions at [node-github](http://mikedeboer.github.io/node-github/#Client.prototype.authenticate).

##### email.fields
For config of these follow instructions at [Nodemailer](https://github.com/andris9/Nodemailer#e-mail-message-fields).

##### email.smtp
For config of these follow instructions at [Nodemailer](https://github.com/andris9/Nodemailer#setting-up-smtp).

##### email.template
An object with two [Eco](https://github.com/sstephenson/eco) templates for building the email. Plaintext is auto-generated from the HTML version.

And finally start it all up (exceptions are thrown, nothing is exported):

```bash
$ node index.js
```

There is also a service on `/` started on an automatic port or one specified through command line.