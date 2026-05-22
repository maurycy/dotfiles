# history - HISTFILE setup, a daily archival pass that keeps the live
# file small, and a zshaddhistory hook that drops secret-looking lines.
setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

HISTFILE=~/.zsh_history
HISTSIZE=10000000000000000
SAVEHIST=10000000000000000

# keep ~/.zsh_history private (zsh would otherwise create/leave it 0644).
# pre-create when missing - chmod alone runs before zsh writes the file.
if [[ ! -L $HISTFILE && ( -f $HISTFILE || ! -e $HISTFILE ) ]]; then
  [[ -e $HISTFILE ]] || : >> "$HISTFILE"
  chmod 600 "$HISTFILE"
fi

# keep the live HISTFILE small so startup stays fast: once a day, when it
# grows past keep+slack entries, move the oldest down to keep entries into
# an archive under $XDG_STATE_HOME instead of deleting them. one writer at
# a time via a lock.
() {
  emulate -L zsh
  local keep=40000 slack=10000
  local arch="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history/zsh_history"
  local pending="$arch.pending"
  local stamp="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history_archived"
  local lock="$stamp.lock"
  [[ -f $HISTFILE ]] || return
  local recent=( $stamp(N.mh-24) )
  (( $#recent )) && return
  mkdir -p "${stamp:h}" && chmod 700 "${stamp:h}"
  # break a stale lock only if its owner process is gone - a lock held by a
  # suspended shell stays valid (wall-clock age is unreliable on a laptop)
  if [[ -d $lock ]]; then
    local lockpid=''
    [[ -r "$lock/pid" ]] && lockpid=$(<"$lock/pid")
    if [[ -z $lockpid ]] || ! kill -0 "$lockpid" 2>/dev/null; then
      rm -f "$lock/pid" 2>/dev/null
      rmdir "$lock" 2>/dev/null
    fi
  fi
  mkdir "$lock" 2>/dev/null || return
  print -r -- "$$" > "$lock/pid"
  local oldumask; oldumask=$(umask); umask 077
  {
    mkdir -p "${arch:h}" && chmod 700 "${arch:h}"
    # a symlink planted at the archive/pending path would redirect history
    # writes off-target - drop it so writes land on a real file we own
    [[ -L $arch ]] && rm -f "$arch"
    [[ -L $pending ]] && rm -f "$pending"
    # umask 077 covers a freshly created archive; tighten an existing one too
    [[ -f $arch ]] && chmod 600 "$arch"
    # recover entries parked by a previous interrupted run
    [[ -f $pending ]] && { cat "$pending" >> "$arch" && rm -f "$pending"; }
    local total
    total=$(LC_ALL=C grep -cE '^: [0-9]+:' "$HISTFILE")
    if (( $? <= 1 )); then
      if (( total > keep + slack )); then
        local old new
        old=$(mktemp "$HISTFILE.old.XXXXXX") && new=$(mktemp "$HISTFILE.new.XXXXXX")
        if [[ -n $old && -n $new ]] && \
           LC_ALL=C awk -v cut=$((total - keep)) -v tot="$total" \
                       -v old="$old" -v new="$new" '
             /^: [0-9]+:/ { n++ }
             { if (n <= cut) print > old; else if (n <= tot) print > new }
           ' "$HISTFILE" && [[ -s $old && -s $new ]]; then
          # the main awk above is bounded at $total, so entries another shell
          # appended after that snapshot (n>total) can be carried into $new
          # here with no double-counting; the mv below then cannot clobber them
          LC_ALL=C awk -v skip="$total" '/^: [0-9]+:/{n++} n>skip' \
            "$HISTFILE" >> "$new"
          # park removed entries, commit the trim, then merge into the
          # archive: a crash after the trim leaves $pending for recovery
          mv -f "$old" "$pending" && mv -f "$new" "$HISTFILE" && \
            { cat "$pending" >> "$arch" && rm -f "$pending"; } && : > "$stamp"
        fi
        rm -f "$old" "$new"
      else
        : > "$stamp"
      fi
    fi
  } always {
    umask "$oldumask"
    rm -f "$lock/pid" 2>/dev/null
    rmdir "$lock" 2>/dev/null
  }
}
# drop history lines that look like they carry a secret: credential env-var
# assignments, connection strings with an inline password, auth headers.
# return 1 discards the line entirely (history file AND session).
zshaddhistory() {
  emulate -L zsh -o extendedglob
  local line=${1%$'\n'} lc
  lc=${line:l}
  if [[ $lc == (*password=*|*passwd=*|*mysql_pwd=*|*secret=*|*token=*|*api[-_]#key=*|*access[-_]#key=*|*authorization:*|*' bearer '*) ]] \
     || [[ $lc == *://[^/:[:space:]]#:[^/[:space:]]##@* ]]; then
    return 1
  fi
  return 0
}
