# bun - javascript runtime & toolkit. completion is sourced lazily from
# ~/.bun on the first `bun` <Tab>.
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && path=("$BUN_INSTALL/bin" $path)

if [[ -r "$HOME/.bun/_bun" ]]; then
  _bun_load() { _is_safe_source "$HOME/.bun/_bun" && source "$HOME/.bun/_bun" }
  _lazy_load _bun_load _bun
  compdef _bun bun
fi
