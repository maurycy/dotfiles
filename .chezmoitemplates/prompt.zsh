# prompt - vcs_info-driven PS1, recomputed in precmd and on SIGWINCH.
# PS1 embeds the already-expanded ${vcs_info_msg_0_}; keep PROMPT_SUBST off so
# a branch name can never be re-evaluated as a command at render time.
unsetopt PROMPT_SUBST
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' get-revision true
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git*+set-message:*' hooks git-untracked
+vi-git-untracked() {
  if git rev-parse --is-inside-work-tree &>/dev/null && \
     [[ -n $(git ls-files --others --exclude-standard 2>/dev/null) ]]; then
    hook_com[unstaged]+='?'
  fi
}
zstyle ':vcs_info:git:*' formats '(%b %.7i%u%c)'
_set_prompt() {
  # double any '%' in the vcs string so a branch name cannot inject a prompt
  # escape (PROMPT_SUBST is off, so this is the only render-time vector left)
  local vcs=${vcs_info_msg_0_//\%/%%}
  # Pick the form by how wide the long prompt would actually render, not by a
  # fixed COLUMNS cut-off: a long path or branch overflows even a wide window.
  # ${(%)...} expands the prompt escapes in-process (no fork), so ${#rendered}
  # is the visible width; fall back to the short form past ~70% of the line.
  local long="%D{%Y-%m-%dT%H:%M:%S.%N%z} %n@%m %d ${vcs} %# "
  local rendered=${(%)long}
  if (( ${#rendered} > ${COLUMNS:-80} * 7 / 10 )); then
    PS1="%(?..[%?] )%n@%B%m%b %1~ ${vcs} %# "
  else
    PS1="%(?..[%?] )%D{%Y-%m-%dT%H:%M:%S.%N%z} %n@%B%m%b %d ${vcs} %# "
  fi
}
precmd() {
  vcs_info
  _set_prompt
}
TRAPWINCH() {
  _set_prompt
  zle && zle reset-prompt
}
