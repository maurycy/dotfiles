# CLAUDE.md

## What this is

chezmoi-managed dotfiles. This repo is the chezmoi *source* directory;
`chezmoi apply` renders it into `~`, so editing a file here changes
nothing until `apply` runs. Filenames carry chezmoi's source-state
attributes (`dot_`, `private_`, `.tmpl`, ...) - the authoritative
reference for those is `chezmoi help` and the chezmoi documentation, not
this file.

## Validating changes

CI is `.github/workflows/validate.yml` - read it for the current checks
(it renders the templates, syntax-checks the rendered zsh, and dry-run
applies, on both Ubuntu and macOS).

For behavioral zsh testing, never use the real `~`: build a sandbox with
an isolated `HOME`, `ZDOTDIR`, `XDG_CACHE_HOME` and `XDG_STATE_HOME`,
render the config into it, and run `zsh -l -i` there. The config mutates
`~/.zsh_history`, caches and (optionally) `~/.secrets` at startup, so an
un-sandboxed run touches real files.

## zsh gotchas (learned the hard way)

- **Arithmetic bases.** Inside `(( ))` a bare `0NN` is read as DECIMAL,
  not octal (`OCTAL_ZEROES` is off by default). And `BASE#NN` notation
  (e.g. `8#22`) poisons the shell's integer output base, so later
  `local -i` / `typeset -i` integers print in that base - this silently
  broke `vcs_info`'s `max-exports`. For permission bit masks use plain
  decimal literals: `18` is octal `022`, `63` is octal `077`.
- `.zshenv` is sourced for EVERY zsh, including non-interactive ones (ssh
  commands, cron, scripts). Keep it minimal and do not `source` external
  scripts there - put a directory on `PATH` directly instead.
- Startup is aggressively performance-tuned - do not add work to the
  startup path.
- A file that gets `source`d is arbitrary code execution. New code that
  sources a path under `$HOME` should validate it first (see the
  `_is_safe_source` helper in `private_dot_zshenv`).

## Files not in this repo - leave alone

`~/.zshrc.local` and `~/.secrets` are user-local files sourced at the end
of `.zshrc`. They are not tracked here. Do not read, copy, modify or
commit them; treat their contents as out of scope.
