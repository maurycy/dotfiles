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
  # 2026-10 eMudhra CA compromise (mozilla bug 2083449): Apple's curl and
  # libcurl verify against /etc/ssl/cert.pem with no revocation, and that
  # file still carries the affected roots. brew fetches with the system curl
  # unless forced, and brew's git links the system libcurl, so both trusted
  # the forged chains in a direct test. point them at brew's Mozilla bundle,
  # which no longer carries those roots. plain [[ -r ]]: no fork.
  [[ -x /opt/homebrew/opt/curl/bin/curl ]] && export HOMEBREW_FORCE_BREWED_CURL=1
  [[ -r /opt/homebrew/etc/ca-certificates/cert.pem ]] && \
    export GIT_SSL_CAINFO=/opt/homebrew/etc/ca-certificates/cert.pem
fi