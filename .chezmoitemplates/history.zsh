# history - HISTFILE setup, a daily pass that deletes entries older than
# three days, and a zshaddhistory hook that drops secret-looking lines.
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

# keep only the last few days of history: once a day, delete entries older
# than $days from the live HISTFILE. nothing is archived - the archive older
# versions of this config kept under $XDG_STATE_HOME is deleted too. one
# writer at a time via a lock.
() {
  emulate -L zsh
  zmodload zsh/datetime
  local days=3
  local arch="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history/zsh_history"
  local stamp="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history_trimmed"
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
    rm -f "$arch" "$arch.pending"
    rmdir "${arch:h}" 2>/dev/null
    # an entry is its ": ts:elapsed;" line plus any continuation lines, and
    # lives or dies by that timestamp; awk prints how many entries it dropped
    local new dropped
    new=$(mktemp "$HISTFILE.new.XXXXXX")
    if [[ -n $new ]] && dropped=$(LC_ALL=C awk -v cut=$((EPOCHSECONDS - days * 86400)) \
         -v new="$new" '
           /^: [0-9]+:/ { k = ($2 + 0 >= cut); if (!k) d++ }
           k { print > new }
           END { print d + 0 }
         ' "$HISTFILE"); then
      if (( dropped )); then
        mv -f "$new" "$HISTFILE" && : > "$stamp"
      else
        : > "$stamp"
      fi
    fi
    [[ -n $new ]] && rm -f "$new"
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
