# CLAUDE.md

These are dotfiles managed by chezmoi. The repository you are looking at
is chezmoi's *source* directory, not a home directory: `chezmoi apply`
renders it into `~`, and editing a file here changes nothing until
`apply` runs. The chezmoi attributes encoded in the filenames - `dot_`,
`private_`, `.tmpl` and the rest - are documented by `chezmoi help`,
which is the authority on them, not this file.

## Testing changes

CI lives in `.github/workflows/validate.yml`: it renders the templates,
syntax-checks the rendered zsh, and does a dry-run apply, on both Ubuntu
and macOS. Read it for the current details.

What CI cannot do is run the shell, and most of what goes wrong here
only shows up in a running shell. So for anything behavioral, build a
sandbox - a throwaway `HOME` with `ZDOTDIR`, `XDG_CACHE_HOME` and
`XDG_STATE_HOME` pointed inside it - render the config there, and start
`zsh -l -i`. This is not fussiness. The config rewrites `~/.zsh_history`,
regenerates caches, and sources `~/.secrets` the moment it starts; point
it at your real home directory and it edits your real home directory.

When something breaks, resist the urge to theorize. Reproduce it to
ground truth with controlled inputs - an empty or fake file tells you
whether the fault is in the code path or in the content far faster than
reading the code will. A long detour in this repo's history was spent
suspecting `~/.secrets`; an empty `~/.secrets` reproduced the bug in
seconds and ended the argument.

## A zsh arithmetic trap

zsh arithmetic has a trap worth knowing before you touch a permission
check. Inside `(( ))` a bare `0NN` is decimal, not octal - `OCTAL_ZEROES`
is off by default - so `022` is twenty-two. The obvious correction, the
explicit `8#22`, is worse: a `BASE#NN` literal sets the integer output
base for the whole shell, and from then on every `local -i` and
`typeset -i` prints in that base, including `maxexports` buried inside
`vcs_info`. The visible symptom was `vcs_info` complaining about
`max-exports` on every prompt; the real cause was a bit mask three files
away. Write masks as plain decimals: `18` for octal `022`, `63` for
octal `077`.

That bug passed `zsh -n`, passed `chezmoi apply --dry-run`, and slipped
through code review. A started shell caught it in one line of output. A
syntax check tells you the file parses; it tells you nothing about what
the shell then does.

## Speed

The README promises that every millisecond counts, and the history backs
it up: interactive startup has come down roughly 129ms -> 70ms -> 33ms ->
13ms across a run of perf PRs. Treat `zsh -i` startup as a fixed budget.

There is a floor. An empty user config still costs about 7.4ms on macOS -
2.4ms or so to spawn the process, the rest in the system `/etc/zprofile`,
which forks `path_helper`, and `/etc/zshrc`, which forks `locale`. You
cannot get under that, so do not spend time trying.

Measure; do not estimate. `time` and `/usr/bin/time -p` have 10ms
resolution and are useless at this scale. Average `EPOCHREALTIME` over
many runs instead:

```
zsh -fc 'zmodload zsh/datetime; t=0; n=120
  for i in {1..$n}; do s=$EPOCHREALTIME; zsh -ic exit
    t=$((t+EPOCHREALTIME-s)); done
  print $((t/n*1000))'
```

To see where the time goes, `zmodload zsh/zprof` gives a function-level
profile, and xtrace - `PS4='+%D{%s%6.} '` then `zsh -ix -c exit` - gives
a per-line timeline that also catches top-level code zprof misses.

The enemy is fork+exec, about 1.1ms each on Apple Silicon. Every external
command on the startup path - every `cat`, `ls`, `tail`, `$(command)`,
`path_helper`, `locale`, `tput` - is roughly a millisecond. Stay in the
shell instead: `$(<file)` rather than `$(cat file)`, since a bare `<file`
with no command hits zsh's in-process read; values returned through
`REPLY` rather than `x=$(func)`, since a command substitution forks a
subshell even around a shell function; glob qualifiers rather than
`ls | sort | tail` or `find`, where `*(/Non)` means directories,
nullglob, numeric-descending sort, so `[1]` is the newest; `read -r var
< file` for a single read; `typeset -U path fpath` to dedup PATH and
fpath for free.

Work that cannot be made cheap is moved off the startup path. `compinit`
spends 4-5ms parsing `~/.zcompdump`, so it is deferred to the first
`<Tab>`: a stub queues `compdef` calls, and a zle widget bound to `^I`
runs the real `compinit` once and replays the queue. A shell that never
completes anything pays nothing. The price of the trick is that anything
needing `compinit`, `compdef` or `bashcompinit` at startup - gcloud's
`completion.zsh.inc`, for one - has to move into that deferred block too.

Caching helps only if you watch what the cache runs. `_cache_eval` and
`_cache_file` store the output of shell-init commands and regenerate it
when the source binary changes. That buys nothing if the cached output
itself forks: `brew shellenv` emits an `eval $(path_helper)`, so caching
it still forks on every shell - inline the static exports instead.

Order and idempotency matter. brew's environment must be set up after
`/etc/zprofile` has run `path_helper`, or `/opt/homebrew/bin` lands
behind `/usr/bin`; that is why it cannot move to `.zshenv`. Prepend-style
variables like `INFOPATH` and `MANPATH` collect duplicates across nested
shells unless you check for containment before exporting. And do not
source the same file from both `.zshenv` and `.zshrc` - `.zshenv` runs
first.

`$commands` is a rebuild trigger, not a lookup. zsh keeps a hash of
every executable on `PATH`; the first read of the `$commands` parameter
builds it, and the first read after any `path=(...)` change rebuilds the
whole thing by rescanning every directory on `PATH`. Consolidating the
per-tool snippets into one block put uv's `$commands` read just after
bun and gcloud had prepended to `PATH`, so the hash `zoxide` built
seconds earlier was thrown away and built again - a second rescan of
`/opt/homebrew/bin` and the rest, about 2ms, for code textually
identical to what shipped before. Keep a `$commands` or `$+commands`
read ahead of every nearby `path=(...)`; uv is deliberately the first
tool snippet for exactly this reason. It was slow to find: the rendered
file was byte-equivalent, `zprof` saw nothing because the cost is
top-level, and one xtrace run could not separate 2ms from its own noise
- averaging per-section checkpoints over a couple hundred starts was
what localized it.

When a question is about zsh itself, read the zsh C source rather than
guess. That `$(<file)` is fork-free, what the glob qualifiers mean, and
whether a function may `unfunction` itself mid-run were all settled that
way. For whitespace-sensitive template work, render with `chezmoi
execute-template` and `cmp` against a saved baseline.

## Security

This config was hardened on purpose - see the `sec:` commit, PR #44 -
and the measures are load-bearing. Each one has a comment in the code
explaining itself. The task when editing is to recognize them and not
quietly undo them while cleaning something else up.

Be honest about the threat they answer. It is the accident: a
world-writable file, a symlink where a real file should be, a secret
that leaks into history, a mode left too loose. It is not a hostile
process already running as you - that process can edit these dotfiles
directly, and no locking changes that. Harden against the accident, and
do not add privilege machinery for an attacker the model does not claim
to stop.

Sourcing a file is running it. Every `source` or `.` of a path under
`$HOME`, `$XDG_*`, or a tool cache passes `_is_safe_source` first, which
refuses anything that is not a plain file, owned by you, with no symlink
in the way and no group or other write bit; a new `source` does the
same. Nothing should `eval "$(some-tool init)"` straight from a mutable
home path - route it through `_cache_file` / `_cache_eval`, which caches
and then validates.

`fpath` and `PATH` are the same kind of surface. A function autoloaded
from `fpath` is code, so only directories you own and nobody else can
write belong there. Do not prepend broad or writable directories to
`PATH`. And leave `compinit` alone: `-u` and `-i` skip its security
check, and the fast path already uses `-C`, which trusts the dump - safe
only as long as `fpath` is.

Keep file modes tight. The history file, its archive, and the shell-init
caches are `0600`, their directories `0700`. `umask 077` around the code
that creates them handles new files; a file that already exists keeps
its old mode, so it gets an explicit `chmod` too. Anything the config
newly writes that holds history, secrets, or cached code is `0600`.

Secrets stay out of two places: the history file and the repository.
`zshaddhistory` drops command lines that look like they carry a secret
by returning 1 - keep that, and do not narrow what it matches. Nothing
renders chezmoi template data or a secret into a tracked file, a cache,
a comment, debug output, or a test fixture; tests use fake data. Real
credentials live in `~/.secrets`, which is not in this repo.

The prompt must never run its own data. `PROMPT_SUBST` is off so that a
branch name or a `vcs_info` field cannot be evaluated as a command while
the prompt renders, and `%` coming from `vcs_info` is escaped. Do not
`setopt PROMPT_SUBST`; if a future prompt truly needs it, every `$(...)`,
`${...}` and `%` that can reach `PS1` has to be neutralized first.

Write to the filesystem carefully. Temp files come from `mktemp`, never a
guessable `$$`, PID, or timestamp name. A symlink already sitting at a
write target is removed before anything is written through it. A commit
to a real path is an atomic `mv`. Keep array and path expansions quoted -
`"${cmd[@]}"`, `"${cache:h}"`, `"$HOME/..."` - because un-quoting them
quietly brings back word-splitting and globbing bugs.

Finally, mind `.zshenv`. It is sourced by every zsh there is, the
non-interactive ones behind cron, `ssh host cmd` and scripts included.
Nothing external is `source`d from there; if something needs to be on
`PATH`, put its directory on `PATH` directly.

## Not in this repo

`~/.zshrc.local` and `~/.secrets` are sourced at the end of `.zshrc` but
are not tracked here - they are yours, local, and out of scope. Do not
read them, copy them, modify them, or commit them.
