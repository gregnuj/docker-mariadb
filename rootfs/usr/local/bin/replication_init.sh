#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source swarm_common.sh
source mysql_common.sh

# Defaults to replication.cnf
function replication_cnf(){
    REPLICATION_CNF="${REPLICATION_CNF:="$(mysql_confd)/replication.cnf"}"
    echo "${REPLICATION_CNF}"
}

function replication_master(){
    REPLICATION_MASTER="${REPLICATION_MASTER:="master"}"
    echo "$REPLICATION_MASTER"
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
    REPLICATION_USERS_SQL="/etc/initdb.d/users.sql"
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'127.0.0.1' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'127.0.0.1';"  >> "$REPLICATION_USERS_SQL"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'localhost' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'localhost';" >> "$REPLICATION_USERS_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$REPLICATION_USERS_SQL"
    echo "Created user $REPLICATION_USER"
}

function replication_init_xtrabackup(){
    source xtrabackup_cnf.sh
}

function replication_init_master(){
    REPLICATION_MASTER_CNF="/etc/mysql/conf.d/master.cnf"
    REPLICATION_MASTER_SQL="/etc/initdb.d/master.sql"
    echo "[mariadb]" >> "$REPLICATION_MASTER_CNF"
    echo "server_id=1" >> "$REPLICATION_MASTER_CNF"
    echo "log-bin" >> "$REPLICATION_MASTER_CNF"
    echo "log-basename=master1" >> "$REPLICATION_MASTER_CNF"
}

function replication_init_slave(){
    REPLICATION_SLAVE_CNF="/etc/mysql/conf.d/slave.cnf"
    REPLICATION_SLAVE_SQL="/etc/initdb.d/slave.sql"
    echo "CHANGE MASTER TO" >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_HOST='$(replication_master)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_USER='$(replication_user)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_PASSWORD='$(replication_password)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_PORT=3306," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_CONNECT_RETRY=10;" >> "$REPLICATION_SLAVE_SQL"
    echo "START SLAVE;" >> "$REPLICATION_SLAVE_SQL"
    echo "[mariadb]" >> "$REPLICATION_SLAVE_CNF"
    echo "server_id=$(node_number)" >> "$REPLICATION_SLAVE_CNF"
}

function main(){
    replication_init_user
    case "${REPLICATION_METHOD}" in
        xtrabackup*)
            GALERA_INIT=1
            replication_init_xtrabackup
            ;;
        master)
            MASTER_INIT=1
            replication_init_master
            ;;
        slave)
            SLAVE_INIT=1
            replication_init_slave
            ;;
    esac
}

main "$@"

