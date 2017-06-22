#!/bin/bash

set -eo pipefail
shopt -s nullglob

# Create/Modify config files based on env
source "config_editor.sh"

declare WANTHELP=$(echo "$@" | grep '\(-?\|--help\|--print-defaults\|-V\|--version\)')
declare -a cmd=( "$*" )

# Set 'DEBUG=1' environment variable to see detailed output for debugging
if [[ -n "$DEBUG" ]]; then
    set -x
fi

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

# Configure replication if REPLICATION_METHOD is set
if [[ ! -z "${REPLICATION_METHOD}" ]]; then
    source replication_init.sh
fi

# Set env MYSQLD_INIT to trigger setup 
if [[ ! -d "$(mysql_datadir)/mysql" ]]; then
    MYSQLD_INIT=${MYSQLD_INIT:=1}
fi

# Configure database if MYSQLD_INIT is set
if [[ ! -z "${MYSQLD_INIT}" ]]; then
    source mysql_init.sh
fi

#  recover galera/xtrabackup
if [[ ! -z "${GALERA_INIT}" ]]; then
    if [[ -f "$(grastate_dat)" ]]; then
        mysqld ${cmd[@]:1} --wsrep-recover
    fi
    if [[ ! -z $(is_primary_component) ]]; then
        if [[ -f "$(grastate_dat)" ]]; then
            sed -i -e 's/^safe_to_bootstrap: *0/safe_to_bootstrap: 1/' $(grastate_dat)
        fi
        cmd+=( " --wsrep-new-cluster" )
    fi
fi

exec ${cmd[*]} 2>&1
