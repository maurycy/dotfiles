# Retain eight hours on disk. All configured shells use one lock for append,
# expiry, and import. SAVEHIST=0 prevents an automatic exit-time rewrite from
# restoring expired entries held in an older shell's memory.
setopt EXTENDED_HISTORY
unsetopt APPEND_HISTORY INC_APPEND_HISTORY INC_APPEND_HISTORY_TIME SHARE_HISTORY
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=0

_history_remove() {
  local helper="$HOME/.local/bin/prm"
  if _is_safe_source "$helper" && [[ -x $helper ]]; then
    "$helper" --files-only -- "$@"
  else
    command rm -f -- "$@"
  fi
}

_history_sync() {
  emulate -L zsh
  setopt EXTENDED_HISTORY HIST_FCNTL_LOCK
  [[ -n $HISTFILE ]] || return 0
  zmodload zsh/datetime
  zmodload zsh/system || return 1
  _is_safe_parent "$HISTFILE" || return 1
  local lock="$HISTFILE.retention.lock" state="$HISTFILE.retention"
  local fd new='' old='' saved='' next=0 dropped=0
  local -A info
  local SAVEHIST=$HISTSIZE
  {
    # noclobber lets simultaneous first shells create these files safely.
    if [[ ! -e $HISTFILE && ! -L $HISTFILE ]]; then
      ( umask 077; setopt NOCLOBBER; : > "$HISTFILE" ) 2>/dev/null
    fi
    if [[ ! -e $lock && ! -L $lock ]]; then
      ( umask 077; setopt NOCLOBBER; : > "$lock" ) 2>/dev/null
    fi
    _is_safe_source "$HISTFILE" || return 1
    _is_safe_source "$lock" strict || return 1
    zsystem flock -t 2 -i 0.02 -f fd "$lock" || return 1
    if [[ ! -e $state && ! -L $state ]]; then
      ( umask 077; setopt NOCLOBBER; : > "$state" ) 2>/dev/null
    fi
    _is_safe_source "$state" strict || return 1
    zstat -H info -- "$HISTFILE" || return 1
    (( (info[mode] & 63) == 0 )) || chmod 600 "$HISTFILE" || return 1
    # The state caches the earliest expiry and the corresponding file metadata.
    # A new shell can skip the scan until that entry expires or the file changes.
    saved=$(<"$state")
    local metadata="$info[device] $info[inode] $info[size] $info[mtime]"
    if [[ ${saved#* } == $metadata && ${saved%% *} == <1-> ]]; then
      next=${saved%% *}
    fi
    [[ $1 == init ]] || fc -AI "$HISTFILE"
    if (( _history_pending_time > 0 && next > _history_pending_time + 8 * 3600 )); then
      next=$((_history_pending_time + 8 * 3600))
    fi
    if (( next <= EPOCHSECONDS )); then
      new=$(mktemp "$HISTFILE.new.XXXXXX") || return 1
      local result
      result=$(LC_ALL=C awk -v cut=$((EPOCHSECONDS - 8 * 3600)) -v new="$new" '
        # A trailing backslash continues the same entry, even if the next line
        # looks like an extended-history timestamp.
        !cont && /^: [0-9]+:[0-9]+;/ {
          t = $0; sub(/^: /, "", t); sub(/:.*/, "", t)
          keep = (t + 0 >= cut)
          if (keep && (!oldest || t + 0 < oldest)) oldest = t + 0
        }
        { if (keep) lines[++n] = $0; else dropped++
          cont = ($0 ~ /\\$/) }
        END {
          if (dropped) for (i = 1; i <= n; i++) print lines[i] > new
          print dropped + 0, (oldest ? oldest : cut + 28800) + 28801
        }
      ' "$HISTFILE") || return 1
      dropped=${result%% *}
      next=${result#* }
    fi
    if (( dropped )); then
      # Keep a link to the old inode until after the atomic replacement.
      # prm overwrites it only when no other hard links remain.
      old=$(mktemp "$HISTFILE.old.XXXXXX") || return 1
      ln -f "$HISTFILE" "$old" || return 1
      mv -f "$new" "$HISTFILE" || return 1
      new=''
    elif [[ -n $new ]]; then
      # No history data was written to this empty scratch file.
      command rm -f -- "$new"
      new=''
    fi
    zstat -H info -- "$HISTFILE" || return 1
    local updated="$next $info[device] $info[inode] $info[size] $info[mtime]"
    [[ $saved == $updated ]] || print -r -- "$updated" > "$state"
    _history_pending_time=0
    [[ $1 == init ]] || fc -RI "$HISTFILE"
  } always {
    [[ -z $new ]] || _history_remove "$new"
    [[ -z $old ]] || _history_remove "$old"
    [[ -z $fd ]] || zsystem flock -u "$fd"
  }
  return 0
}

typeset -g _history_pending_time=0
_history_sync init || {
  print -u2 "history: persistence disabled: unsafe path or failed update"
  HISTFILE=''
}
# Retire archives from the former history configuration.
() {
  local arch="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history/zsh_history"
  if [[ -e $arch || -L $arch || -e $arch.pending || -L $arch.pending ]]; then
    _history_remove "$arch" "$arch.pending"
  fi
}
# Expiry runs at startup, each prompt, and exit. Sleeping or closed shells do
# not run a timer. Old events can remain in an open shell's in-memory history.
typeset -ga precmd_functions zshexit_functions
precmd_functions+=( _history_sync )
zshexit_functions+=( _history_sync )

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
  (( _history_pending_time )) || _history_pending_time=$EPOCHSECONDS
  return 0
}
