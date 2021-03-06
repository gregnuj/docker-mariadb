#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

function mysql_datadir(){
    DATADIR="${DATADIR:="/var/lib/mysql"}"
    echo "$DATADIR"
}

function grastate_dat(){
    GRASTATE_DAT="${GRASTATE_DAT:="$(mysql_datadir)/grastate.dat"}"
    echo "${GRASTATE_DAT}"
}

function mysql_confd(){
    MYSQL_CONFD="{$MYSQL_CONFD:=/etc/mysql/conf.d}"
    mkdir -p "${MYSQL_CONFD}"
    echo "${MYSQL_CONFD}"
}

function mysql_user(){
    if [[ -n "$1" ]]; then
        USER="$1"
    else
        USER=${MYSQL_USER:="root"}
    fi
    echo "$USER"
}

function mysql_password(){
    USER="$(mysql_user $1)"
    if [[ $USER == "root" ]]; then
        PASSWORD="${MYSQL_ROOT_PASSWORD:="${MYSQL_ROOT_PASSWORD_FILE}"}"
    elif [[ $USER == "${MYSQL_USER}" ]]; then
        PASSWORD="${MYSQL_PASSWORD:="${MYSQL_PASSWORD_FILE}"}"
    fi

    if [[ -r "$PASSWORD" ]]; then
        PASSWORD="$(cat "$PASSWORD")"
    elif [[ -z "$PASSWORD" && -r "/var/run/secrets/$USER" ]]; then
        PASSWORD="$(cat "/var/run/secrets/${USER}")"
    elif [[ -z "$PASSWORD" ]]; then
        PASSWORD="$(echo "$USER:$MYSQL_ROOT_PASSWORD" | sha256sum | awk '{print $1}')"
    fi

    echo "${PASSWORD}"
}

function mysql_shutdown(){
    MYSQL_SHUT=( "mysqladmin" )
    MYSQL_SHUT+=( "shutdown" )
    MYSQL_SHUT+=( "-u$(mysql_user root)" )
    MYSQL_SHUT+=( "-p$(mysql_password root)" )
    "${MYSQL_SHUT[@]}"
}

function mysql_client(){
    MYSQL_CLIENT=( "mysql" )
    MYSQL_CLIENT+=( "--protocol=socket" )
    MYSQL_CLIENT+=( "--socket=/var/run/mysqld/mysqld.sock" )
    MYSQL_CLIENT+=( "-hlocalhost" )
    MYSQL_CLIENT+=( "-u$(mysql_user root)" )
    MYSQL_CLIENT+=( "-p$(mysql_password root)" )
    echo "${MYSQL_CLIENT[@]}"
}

function replication_user(){
    REPLICATION_USER="${REPLICATION_USER:="replication"}"
    echo "$REPLICATION_USER"
}

function replication_password(){
    REPLICATION_PASSWORD="${REPLICATION_PASSWORD:="$(mysql_password "$(replication_user)")"}"
    echo "$REPLICATION_PASSWORD"
}

function main(){
    case "$1" in
        -a|--auth)
            echo "$(mysql_auth $2)"
            ;;
        -d|--dir)
            echo "$(mysql_datadir)"
            ;;
        -p|--password)
            echo "$(mysql_password $2)"
            ;;
        -u|--user)
            echo "$(mysql_user $2)"
            ;;
    esac
}

main "$@"
