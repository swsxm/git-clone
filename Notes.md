## everything is taken from: https://stefan.saasen.me/articles/git-clone-in-haskell-from-the-bottom-up/#reimplementing-git-clone-in-haskell-from-the-bottom-up

# Git Daemon + Protocol Notes

## Serving over git://

Only works with _bare_ repositories.
Repositories must contain a `git-daemon-export-ok` file to be served.

To start a simple Git daemon from the current directory:

```bash
/usr/lib/git-core/git-daemon \
  --reuseaddr \
  --base-path=. \
  --export-all \
  --verbose \
  --enable=receive-pack \
  --port=9418
```

To test if it works:

```bash
git ls-remote git://127.0.0.1/test.git
```

This should return refs if `test.git` is a valid bare repo and is exportable.

## What happens under the hood

When `git ls-remote` or `git clone` is executed with a `git://` URL:

- A TCP connection is opened to port 9418
- The client sends a packet with the requested command and path
- This triggers the "ref discovery" step on the server

Example of the request sent by the client (wire format):

```
0032git-upload-pack /test\0host=localhost\0
```

- `0032` is the packet length (32 bytes in hex)
- `git-upload-pack` = operation (used for cloning/fetching)
- `/test` = the repository path (relative to base-path)
- `host=localhost` is optional

## ABNF-style protocol layout

Rough definition of the Git request in ABNF:

```
git-proto-request = request-command SP pathname NUL [ host-parameter NUL ]
request-command   = "git-upload-pack" / "git-receive-pack" / "git-upload-archive"
pathname          = *(any byte except NUL)
host-parameter    = "host=" hostname [ ":" port ]
```
