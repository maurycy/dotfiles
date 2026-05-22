# nvm - node version manager. node/npm/npx are pinned onto PATH below as
# plain binaries; only the `nvm` command itself needs nvm.sh, deferred
# via _lazy_load.
export NVM_DIR="$HOME/.nvm"

if [ -d "$NVM_DIR/versions/node" ]; then
  # resolver runs fork-free: $(<file) is read internally by zsh, and the
  # result is returned via REPLY so the caller avoids a $() subshell too.
  _nvm_resolve_alias() {
    local alias="$1" target
    while [ -f "$NVM_DIR/alias/$alias" ]; do
      target=$(<"$NVM_DIR/alias/$alias")
      [[ "$target" == v* ]] && { REPLY="$target"; return; }
      alias="$target"
    done
    if [ -f "$NVM_DIR/alias/lts/$alias" ]; then
      REPLY=$(<"$NVM_DIR/alias/lts/$alias")
    else
      REPLY="$alias"
    fi
  }
  _nvm_resolve_alias default
  NODE_VER="$REPLY"
  # _is_safe_dir checks the actual bin dir we are about to prepend to PATH,
  # not just the parent version directory.
  if _is_safe_dir "$NVM_DIR/versions/node/$NODE_VER/bin"; then
    path=("$NVM_DIR/versions/node/$NODE_VER/bin" $path)
  else
    # newest installed version via glob: (/) dirs, (N) nullglob,
    # (On) numeric descending sort -> [1] is the latest
    _node_vers=( "$NVM_DIR"/versions/node/*(/Non) )
    (( $#_node_vers )) && _is_safe_dir "${_node_vers[1]}/bin" && \
      path=("${_node_vers[1]}/bin" $path)
    unset _node_vers
  fi
  unset -f _nvm_resolve_alias
fi
if [ -s "$NVM_DIR/nvm.sh" ] || [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  # node/npm/npx run as PATH binaries (pinned above); only `nvm` needs nvm.sh.
  # $NVM_DIR is under $HOME, so its scripts pass _is_safe_source first (regular
  # file, owned by us, no symlink, no group/other write) before being sourced.
  # the /opt/homebrew paths are a brew prefix, not a mutable home path, so they
  # keep the plain -s test.
  _nvm_load() {
    if _is_safe_source "$NVM_DIR/nvm.sh"; then
      \. "$NVM_DIR/nvm.sh"
      _is_safe_source "$NVM_DIR/bash_completion" && \. "$NVM_DIR/bash_completion"
    elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
      \. "/opt/homebrew/opt/nvm/nvm.sh"
    fi
    [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
  }
  _lazy_load _nvm_load nvm
fi
