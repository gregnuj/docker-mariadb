#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source swarm_common.sh
source mysql_common.sh

# Defaults to replication.cnf
function replication_cnf(){
    REPLICATION_CNF="${REPLICATION_CNF:="$(mysql_confd)/replication.cnf"}"
    echo "${REPLICATION_CNF}"
}

function replication_user(){
    REPLICATION_USER="${REPLICATION_USER:="replication"}"
    echo "$REPLICATION_USER"
}

function replication_password(){
    REPLICATION_PASSWORD="${REPLICATION_PASSWORD:="$(mysql_password "$(replication_user)")"}"
    echo "$REPLICATION_PASSWORD"
}

function replication_init_user(){
    mysql=( $(mysql_client) );
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'127.0.0.1' IDENTIFIED BY '${REPLICATION_PASSWORD}';" | "${mysql[@]}"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'127.0.0.1';"    | "${mysql[@]}"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'localhost' IDENTIFIED BY '${REPLICATION_PASSWORD}';" | "${mysql[@]}"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'localhost';"    | "${mysql[@]}"
    echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
    echo "Created user $REPLICATION_USER"
}

function replication_init_xtrabackup(){
    source xtrabackup_cnf.sh
}

function replication_init_master(){
    :
}

function replication_init_slave(){
    :
}

function main(){
    replication_init_user
    case "${REPLICATION_METHOD}" in
        xtrabackup*)
            replication_init_xtrabackup
            GALERA_INIT=1
            ;;
        master)
            replication_init_master
            ;;
        slave)
            replication_init_slave
            ;;
    esac
}

main "$@"

