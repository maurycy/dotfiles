# homebrew environment (static exports; avoids the brew + path_helper forks)
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX="/opt/homebrew"
  export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
  export HOMEBREW_REPOSITORY="/opt/homebrew"
  fpath=("/opt/homebrew/share/zsh/site-functions" $fpath)
  export FPATH
  path=("/opt/homebrew/bin" "/opt/homebrew/sbin" $path)
  [[ ":$INFOPATH:" == *:/opt/homebrew/share/info:* ]] || \
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
  [[ -z "${MANPATH-}" ]] || export MANPATH=":${MANPATH#:}"
fi