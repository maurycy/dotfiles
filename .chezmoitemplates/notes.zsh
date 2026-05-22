# notes - topical markdown knowledge base under $NOTES_DIR
#   n  <name>    create or open a note: $NOTES_DIR/<name>.md
#   ns <query>   search notes; filename matches rank above content matches
#   nf <query>   same as ns
# ripgrep does the searching; fzf (when installed) turns it into an
# interactive picker, otherwise the ranked matches are just printed.

: "${NOTES_DIR:=$HOME/src/github.com/maurycy/prompts/research}"
export NOTES_DIR

# n - create or open a note by name. spaces become hyphens, a missing
# ".md" is appended, and parent folders are created so "n draheim/foo" works.
n() {
  emulate -L zsh
  local name="$*"
  if [[ -z "$name" ]]; then
    print -u2 "usage: n <note-name>"
    return 1
  fi
  name="${name// /-}"
  [[ "$name" == *.md ]] || name+=".md"
  local target="$NOTES_DIR/$name"
  mkdir -p "${target:h}"
  "${EDITOR:-vim}" "$target"
}

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
