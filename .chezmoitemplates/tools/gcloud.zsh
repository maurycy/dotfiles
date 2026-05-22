# google cloud sdk. path.zsh.inc only manipulates PATH, so it loads now.
# completion.zsh.inc needs compdef/bashcompinit, so it is deferred: the
# loader is registered in _post_compinit_hooks and runs inside
# _compinit_real on the first <Tab> (see _compinit_real in .zshrc).
_is_safe_source "$HOME/.local/google-cloud-sdk/path.zsh.inc" && \
  . "$HOME/.local/google-cloud-sdk/path.zsh.inc"

_gcloud_completion_load() {
  _is_safe_source "$HOME/.local/google-cloud-sdk/completion.zsh.inc" && \
    source "$HOME/.local/google-cloud-sdk/completion.zsh.inc"
}
_post_compinit_hooks+=( _gcloud_completion_load )
