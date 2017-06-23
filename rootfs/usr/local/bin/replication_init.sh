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
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'%';" >> "$REPLICATION_USERS_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$REPLICATION_USERS_SQL"
    echo "Created $REPLICATION_USERS_SQL"
}

function replication_init_xtrabackup(){
    source xtrabackup_cnf.sh
}

function replication_init_cnf(){
    REPLICATION_CNF="$(replication_cnf)"
    echo "[mariadb]" >> "$REPLICATION_CNF"
    echo "log-bin" >> "$REPLICATION_CNF"
    echo "log-basename=mysql-bin" >> "$REPLICATION_CNF"
    echo "relay-log=mysql-relay-bin" >> "$REPLICATION_CNF"
    echo "relay-log-index=mysql-relay-bin.index" >> "$REPLICATION_CNF"
    echo "expire_logs_days=15" >> "$REPLICATION_CNF"
    echo "max_binlog_size=512M" >> "$REPLICATION_CNF"
    echo "Created $REPLICATION_CNF"
}

function replication_init_master(){
    REPLICATION_CNF="$(replication_cnf)"
    echo "server_id=1" >> "$REPLICATION_CNF"
    REPLICATION_MASTER_SQL="/etc/initdb.d/master.sql"
    echo "Created $REPLICATION_MASTER_SQL"
}

function replication_init_slave(){
    REPLICATION_CNF="$(replication_cnf)"
    echo "server_id=$(node_number)" >> "$REPLICATION_CNF"
    REPLICATION_SLAVE_SQL="/etc/initdb.d/slave.sql"
    echo "CHANGE MASTER TO" >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_HOST='$(replication_master)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_USER='$(replication_user)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_PASSWORD='$(replication_password)'," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_PORT=3306," >> "$REPLICATION_SLAVE_SQL"
    echo "MASTER_CONNECT_RETRY=10;" >> "$REPLICATION_SLAVE_SQL"
    echo "START SLAVE;" >> "$REPLICATION_SLAVE_SQL"
    echo "Created $REPLICATION_SLAVE_SQL"
}

function main(){
    case "${REPLICATION_METHOD}" in
        xtrabackup*)
            GALERA_INIT=1
            replication_init_xtrabackup
            replication_init_user
            ;;
        master)
            MASTER_INIT=1
            replication_init_cnf
            replication_init_master
            replication_init_user
            ;;
        slave)
            SLAVE_INIT=1
            replication_init_cnf
            replication_init_slave
            replication_init_user
            ;;
    esac
}

main "$@"

