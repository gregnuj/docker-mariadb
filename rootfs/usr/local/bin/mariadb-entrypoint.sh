#!/bin/bash

set -eo pipefail
shopt -s nullglob

# Set 'DEBUG=1' environment variable to see detailed output for debugging
if [[ -n "$DEBUG" ]]; then
    set -x
fi

declare WANTHELP=$(echo "$@" | grep '\(-?\|--help\|--print-defaults\|-V\|--version\)')
declare -a cmd=( "$*" )

# Create/Modify config files based on env
source "config_editor.sh"

# if command starts with an option, prepend mysqld
if [[ "${1:0:1}" = '-' ]]; then
    set -- mysqld "$@"
fi

# command is not mysqld 
if [[ $1 != 'mysqld' && $1 != 'mysqld_safe' ]]; then
    exec "$@"
fi

# command has help param
if [[ ! -z "$WANTHELP" ]]; then
    exec "$@"
fi

# allow the container to be started with `--user`
if [[ "$(id -u)" = '0' ]]; then
    exec gosu mysql "$BASH_SOURCE" "$@"
fi

source mysql_init.sh

exec ${cmd[*]} 2>&1
