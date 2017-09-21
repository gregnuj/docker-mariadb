#!/bin/bash

set -eo pipefail
shopt -s nullglob

# Set 'DEBUG=1' environment variable to see detailed output for debugging
if [[ -n "$DEBUG" ]]; then
    set -x
fi

# capture parameters
declare -a cmd=( "$*" )

# Check for help options
declare WANTHELP=$(echo "$@" | grep '\(-?\|--help\|--print-defaults\|-V\|--version\)')

# if command starts with an option, prepend mysqld
if [[ "${1:0:1}" = '-' ]]; then
    set -- mysqld "${cmd[@]}"
fi

# command is not mysqld 
if [[ $1 != 'mysqld' && $1 != 'mysqld_safe' ]]; then
    exec "${cmd[@]}"
fi

# command has help param
if [[ ! -z "$WANTHELP" ]]; then
    exec "${cmd[@]}"
fi

# allow the container to be started with `--user`
if [[ "$(id -u)" = '0' ]]; then
    exec gosu mysql "$BASH_SOURCE" "${cmd[@]}"
fi

# init database
source mysql_init.sh

# add sql init file, if no other is defined
if [[ $(echo "$@" | grep -v '\(--init-file\)') ]]; then
    cmd+=( --init-file "$(mysql_init_file)" )
fi

exec "${cmd[@]}"
