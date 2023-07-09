# IndieAuth Validation Client

This is a sinatra webserver that acts as a dummy IndieAuth client.  I wrote it to help me implement an IndieAuth provider in Haven.

## Usage

Install the sinatra ruby gem:

```bash
$ gem install sinatra
```

Then run the server:

```bash
$ ruby server.rb
```

You can access the server at `http://localhost:4567`.

Select your desired scopes and enter the url of your IndieAuth provider in the form.

## Links

IndieAuth Spec: https://indieauth.spec.indieweb.org/
Micropub: https://indieweb.org/Micropub
Microsub: https://indieweb.org/Microsub-spec
Haven: https://github.com/havenweb/haven
