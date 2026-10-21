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

# History and document privacy

Zsh uses an eight-hour cutoff for disk history and a 100,000-entry limit.
Expiry runs at startup, at each prompt, and on exit. A cached deadline avoids repeated scans before the oldest entry expires.
Sleeping or closed shells do not run a cleanup timer. An open shell can retain older entries in memory.
All configured shells share a lock for history updates. Automatic exit-time writes are disabled to prevent expired entries from returning.
Restart existing shells after applying this change so that every writer uses the same lock.

Document tools pass `--no-log` to LLM and create new files with private permissions.
This does not remove existing LLM logs or change existing document permissions.

`prm --files-only -- path...` removes only the named files, without searching for identical copies.
It uses `shred` or `gshred` when available and falls back to `rm`.
It does not overwrite symlink targets, multiply linked files, or files owned by another user.
History cleanup and document scratch-file cleanup use this mode.
Overwriting does not guarantee erasure from SSDs, copy-on-write filesystems, snapshots, or backups.

# SSH defaults

SSH adds software keys to the agent for one hour. Agent forwarding and connection sharing are disabled by default.
Host blocks in `~/.ssh/config.d/` can enable connection sharing where subsequent sessions can reuse authentication.
Both `ControlMaster` and `ControlPath` must be set in those blocks.

For managed hosts, verify each host key through a trusted channel and record it in `known_hosts`.
Then add `StrictHostKeyChecking yes` to the corresponding host block.
These defaults retain the current identity file. A migration to Secretive or hardware keys requires separate provisioning and login checks.

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
