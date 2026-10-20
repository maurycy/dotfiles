I'm tired of syncing the same dotfiles between two laptops and servers over and over.

This repository uses [chezmoi](https://www.chezmoi.io/). There are [many ways to install it](https://www.chezmoi.io/install/).

# Usage

Start with:

```bash
chezmoi init maurycy/dotfiles
```

The command the content of the repository to the chezmoi directory (which is `$HOME/.local/share/chezmoi` on macOS and Debian, when I'm typing this.)

Once the dotfiles are fetched, you can audit any potential changes:

```bash
chezmoi diff
```

If you're happy with you see, just apply:

```bash
chezmoi apply
```

You might want to sync with me from time to time:

```
chezmoi update
```

# Caveats

* This is [zsh](https://en.wikipedia.org/wiki/Z_shell) first, but without [oh my zsh](https://ohmyz.sh/), which I find too heavy and too slow.
* Optimized for speed. I start new terminal windows probably thousands times a day, so every millisecond counts.

# TLS certificates

`.zshenv` selects the Homebrew CA bundle on macOS or the Debian/Ubuntu CA bundle on Linux.
Curl, Git, Python with OpenSSL, HTTPX, Requests, and Node use this bundle through environment variables.
This configuration replaces inherited CA paths and disables the additional OpenSSL CA directory.

Programs with explicit CA configuration or disabled environment support can use a different trust store.
Programs outside the zsh process tree do not receive these exports.
Apple's system Python with [LibreSSL](https://docs.python.org/3.10/library/ssl.html#ssl.get_default_verify_paths) ignores `SSL_CERT_FILE` and `SSL_CERT_DIR` for its default SSL context.
For Python HTTPS clients, use a Python build with OpenSSL or pass the CA bundle explicitly.

`tls-ca-trim` builds `~/.config/tls/ca-bundle.pem` from that bundle, keeping only the roots listed in `~/.config/tls/roots.txt`, and `.zshenv` prefers it when present.
Eleven roots anchor every host in daily use; a host under another root fails with a TLS error until its root is added and `tls-ca-trim` is rerun.
`mupdate` reruns it after each update.

Keep the selected `ca-certificates` package current.
On macOS, install Homebrew's `curl` and `ca-certificates` packages before use.
After `chezmoi apply`, start a new shell and restart dependent processes.

For the [eMudhra incident](https://github.com/advisories/GHSA-6q48-6c7w-9gw2), update `certifi` to `2026.10.19` or later in each Python environment.
Include installed uv tools, cached uvx environments, project environments, and container images.
The exports do not update those packages.
For Linux tools written in Go, install binaries built with Go 1.27.3, 1.26.10, or a later patched version.
