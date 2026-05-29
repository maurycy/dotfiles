# notes - topical markdown knowledge base under $NOTES_DIR
#   n            pick a note (newest first; type to filter, or type a new
#                name and press enter to create it)
#   n <name>     create or open $NOTES_DIR/<name>.md directly
#   n cd         cd into $NOTES_DIR itself (the one name that is not a note)
#   ns <query>   search notes; filename matches rank above content matches
#   nf <query>   same as ns
# ripgrep does the searching; fzf (when installed) makes n and ns/nf
# interactive. <Tab> after n completes existing note names.

: "${NOTES_DIR:=$HOME/src/github.com/maurycy/prompts/research}"
export NOTES_DIR

# _notes_edit - open a note in $EDITOR with cwd set to $NOTES_DIR for the
# duration of the edit, so the whole knowledge base is reachable from
# inside the editor (:e, fzf, relative links). The subshell restores the
# caller's cwd on exit automatically; the file path passed in is absolute,
# so the editor opens the right note regardless of cwd. One fork per edit -
# negligible next to launching $EDITOR, and this is interactive, not startup.
_notes_edit() { ( cd "$NOTES_DIR" && "${EDITOR:-vim}" "$1" ) }

# n - open a note. with a name: create or open it (spaces become hyphens,
# ".md" is appended, parent folders are created). without a name: an fzf
# picker over notes newest-first - pick one, or type a name nothing
# matches and press enter to create it.
n() {
  emulate -L zsh

  # `n cd` is the one exception: instead of opening a note named "cd", it
  # jumps the shell into $NOTES_DIR. cd in a function changes the calling
  # shell's directory, which is the point. A real note called "cd" is the
  # price - reach it with `n cd.md`, which falls through to the name path.
  if [[ "$*" == cd ]]; then
    mkdir -p "$NOTES_DIR" && cd "$NOTES_DIR"
    return
  fi

  if [[ -n "$*" ]]; then
    local name="${*// /-}"
    [[ "$name" == *.md ]] || name+=".md"
    local target="$NOTES_DIR/$name"
    mkdir -p "${target:h}"
    _notes_edit "$target"
    return
  fi

  mkdir -p "$NOTES_DIR"
  local -a rel
  rel=( "$NOTES_DIR"/**/*.md(.Nom) )   # .=files N=nullglob om=mtime, newest first
  rel=( ${rel[@]#$NOTES_DIR/} )
  (( ${#rel} )) || { print -u2 "notes: none yet - use 'n <name>' to create one"; return }

  if ! command -v fzf >/dev/null; then
    print -u2 "recent notes (open with 'n <name>'; install fzf for the picker):"
    printf '  %s\n' "${rel[1,5]}"
    return
  fi

  local preview="cat '$NOTES_DIR'/{}"
  command -v bat >/dev/null && \
    preview="bat --style=numbers --color=always '$NOTES_DIR'/{}"

  local out
  out="$(printf '%s\n' "${rel[@]}" \
    | fzf --no-sort --print-query --prompt='note> ' \
          --preview="$preview" --preview-window='right,60%')"
  local rc=$?
  local -a lines=( "${(@f)out}" )
  case $rc in
    0) [[ -n "${lines[2]}" ]] && _notes_edit "$NOTES_DIR/${lines[2]}" ;;  # picked
    1) [[ -n "${lines[1]}" ]] && n "${lines[1]}" ;;                            # typed a new name
  esac                                                                          # 130: aborted
}

# nn - open today's daily note ($NOTES_DIR/daily/YYYY-MM-DD.md).
# Delegates to `n`, which appends .md, creates parent dirs, and opens
# $EDITOR. Date via zsh/datetime (no fork). Both `b:strftime` and
# `p:EPOCHSECONDS` must be listed or the parameter stays unloaded.
nn() {
  emulate -L zsh
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local today
  strftime -s today '%Y-%m-%d' "$EPOCHSECONDS"
  n "daily/$today"
}

# <Tab> after n completes note names under $NOTES_DIR
_notes_n() { _files -W "$NOTES_DIR" -g '*.md' }
(( $+functions[compdef] )) && compdef _notes_n n

# ns / nf - one search over both filenames and content. ripgrep emits two
# blocks: filename matches first, then content matches with line numbers.
# fzf keeps that order via --no-sort, so a filename match always wins.
if command -v rg >/dev/null; then
  _notes_search() {
    emulate -L zsh
    [[ -d "$NOTES_DIR" ]] || {
      print -u2 "notes: \$NOTES_DIR not found: $NOTES_DIR"
      return 1
    }

    local query="$*"
    local -a rows
    local rel rest line

    if [[ -z "$query" ]]; then
      # no query: list every note, by filename
      while IFS= read -r rel; do
        rows+=( "$NOTES_DIR/$rel"$'\t'"1"$'\t'"$rel" )
      done < <(cd "$NOTES_DIR" && command rg --files -g '*.md' 2>/dev/null | sort)
    else
      # block 1: filename matches
      while IFS= read -r rel; do
        [[ -n "$rel" ]] && rows+=( "$NOTES_DIR/$rel"$'\t'"1"$'\t'"$rel" )
      done < <(cd "$NOTES_DIR" && command rg --files -g '*.md' 2>/dev/null \
                 | command rg --fixed-strings --smart-case -- "$query" | sort)
      # block 2: content matches
      while IFS= read -r rest; do
        rel="${rest%%:*}"
        line="${${rest#*:}%%:*}"
        rows+=( "$NOTES_DIR/$rel"$'\t'"$line"$'\t'"$rest" )
      done < <(cd "$NOTES_DIR" && command rg --fixed-strings --smart-case \
                 --line-number --no-heading --color=never -g '*.md' -- "$query" 2>/dev/null)
    fi

    (( ${#rows} )) || { print -u2 "notes: no match for: ${query:-(all)}"; return 1 }

    if command -v fzf >/dev/null; then
      local preview
      if command -v bat >/dev/null; then
        preview='bat --style=numbers --color=always --highlight-line {2} {1}'
      else
        preview='cat {1}'
      fi
      local pick
      pick="$(printf '%s\n' "${rows[@]}" \
        | fzf --no-sort --delimiter=$'\t' --with-nth='3..' --prompt='notes> ' \
              --preview="$preview" --preview-window='right,60%,+{2}/3')" || return
      [[ -n "$pick" ]] || return
      local file="${pick%%$'\t'*}"
      line="${${pick#*$'\t'}%%$'\t'*}"
      "${EDITOR:-vim}" "+${line}" "$file"
    else
      # no fzf: print the ranked matches (filenames first, then content)
      printf '%s\n' "${rows[@]}" | cut -f3-
    fi
  }
  alias ns='_notes_search'
  alias nf='_notes_search'
fi
