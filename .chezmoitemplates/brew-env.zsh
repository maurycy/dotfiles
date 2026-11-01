# homebrew environment (static exports; avoids the brew + path_helper forks)
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX="/opt/homebrew"
  export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
  export HOMEBREW_REPOSITORY="/opt/homebrew"
  # no usage reporting, no https->http downgrade on download redirects,
  # and casks must ship a checksum (all 12 installed ones do)
  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_NO_INSECURE_REDIRECT=1
  export HOMEBREW_CASK_OPTS="--require-sha"
  fpath=("/opt/homebrew/share/zsh/site-functions" $fpath)
  export FPATH
  path=("/opt/homebrew/bin" "/opt/homebrew/sbin" $path)
  [[ ":$INFOPATH:" == *:/opt/homebrew/share/info:* ]] || \
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
  [[ -z "${MANPATH-}" ]] || export MANPATH=":${MANPATH#:}"
fi
