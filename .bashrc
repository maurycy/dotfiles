PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

shopt -s histappend
shopt -s checkwinsize
CW="\[\033[1m\]"
CN="\[\033[0m\]"
export PS1="[$CW\D{%H%M}$CN](\u@\h)$CW\w$CN> "
unset CW CN

export EDITOR=vim
export VISUAL=vim

LANG=en_US.UTF-8
LC_CTYPE=pl_PL.UTF-8
export LANG LC_CTYPE

export GREP_OPTIONS="--color=auto"

alias l='ls -l'
alias ll='ls -lh'
