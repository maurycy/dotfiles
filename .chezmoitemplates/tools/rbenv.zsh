# rbenv - ruby version manager. shims go on PATH; `rbenv init` is
# lazy-loaded on the first `rbenv` call.
if command -v rbenv >/dev/null 2>&1 || [ -d "$HOME/.rbenv" ]; then
  export RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
  [[ -d "$RBENV_ROOT/bin" ]]   && path=("$RBENV_ROOT/bin" $path)
  [[ -d "$RBENV_ROOT/shims" ]] && path=("$RBENV_ROOT/shims" $path)
  _rbenv_load() { eval "$(rbenv init - zsh)" }
  _lazy_load _rbenv_load rbenv
fi
