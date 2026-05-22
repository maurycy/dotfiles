# git - aliases, diff/git-diff dispatch (with completion and a Tab-cycle
# widget), and a worktree subcommand wrapper. all the git ergonomics in
# one place; previously these items sat in five separate spots in .zshrc.
if command -v git >/dev/null; then
  alias add='git add'
  alias ci='git ci'
  alias co='git co'
  alias push='git push'
  alias pull='git pull'
  alias st='git st'
  alias d='git diff'
  alias up='git up'
  alias stash='git stash'
  alias unstash='git stash apply'
  alias spush='git stash push -u'
  alias slist='git stash list'
  alias spop='git stash pop'
  alias sdrop='git stash drop'
  alias merge='git merge'
fi

# diff: dispatch to `git diff` when --cached is passed, plain diff otherwise.
diff() {
  local args=() use_git=0
  for arg in "$@"; do
    if [[ "$arg" == --cach* ]]; then
      args+=(--cached)
      use_git=1
    else
      args+=("$arg")
    fi
  done
  if (( use_git )); then
    git diff "${args[@]}"
  else
    command diff "$@"
  fi
}

_diff() {
  _arguments \
    '--cached[show git staged changes]' \
    '*:file:_files'
}
compdef _diff diff

# tab-cycle between `diff` and `git diff` when the buffer is exactly one
# of them; otherwise fall back to normal completion. wired in by
# _compinit_boot after the deferred compinit finishes (see .zshrc).
_tab_or_diff_cycle() {
  if [[ "$BUFFER" == "diff" ]]; then
    BUFFER="git diff"
    CURSOR=$#BUFFER
  elif [[ "$BUFFER" == "git diff" ]]; then
    BUFFER="diff"
    CURSOR=$#BUFFER
  else
    zle expand-or-complete
  fi
}
zle -N _tab_or_diff_cycle

# worktree - short subcommand aliases (`worktree ls`, `worktree rm`) that
# git itself does not have, with passthrough for everything else.
worktree() {
  case "$1" in
    ls) shift; git worktree list "$@" ;;
    rm) shift; git worktree remove "$@" ;;
    *)  git worktree "$@" ;;
  esac
}
