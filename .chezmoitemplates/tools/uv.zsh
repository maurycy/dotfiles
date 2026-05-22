# uv - python package manager / runner. `python` is routed through uv;
# completion is cached and parsed lazily on the first `uv` <Tab> so the
# ~500K completion script never touches the startup path.
alias python='uv run python'

if (( $+commands[uv] )); then
  _uv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/uv.zsh"
  _cache_file "$_uv_cache" "$commands[uv]" uv generate-shell-completion zsh
  if [[ -s "$_uv_cache" ]]; then
    _uv_load() {
      local c="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/uv.zsh"
      _is_safe_source "$c" strict && source "$c"
    }
    _lazy_load _uv_load _uv
    compdef _uv uv
  fi
  unset _uv_cache
fi
