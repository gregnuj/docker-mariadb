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
    REPLICATION_USERS_SQL="/etc/initdb.d/50-users.sql"
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%';" >> "$REPLICATION_USERS_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$REPLICATION_USERS_SQL"
    echo "Created $REPLICATION_USERS_SQL"
}


function replication_init_sql(){
    REPLICATION_SQL="/etc/initdb.d/60-replication.sql"
    echo "CHANGE MASTER TO" >> "$REPLICATION_SQL"
    echo "MASTER_HOST='$(replication_master)'," >> "$REPLICATION_SQL"
    echo "MASTER_USER='$(replication_user)'," >> "$REPLICATION_SQL"
    echo "MASTER_PASSWORD='$(replication_password)'," >> "$REPLICATION_SQL"
    echo "MASTER_PORT=3306," >> "$REPLICATION_SQL"
    echo "MASTER_CONNECT_RETRY=30;" >> "$REPLICATION_SQL"
    echo "Created $REPLICATION_SQL"
}

function replication_init_cnf(){
    REPLICATION_CNF="$(replication_cnf)"
    echo "[mariadb]" >> "$REPLICATION_CNF"
    echo "skip-name-resolve=0" >> "$REPLICATION_CNF"
    echo "log-bin=mysql-bin" >> "$REPLICATION_CNF"
    echo "binlog-do-db=${APP_NAME}" >> "$REPLICATION_CNF"
    echo "relay-log=mysql-relay-bin" >> "$REPLICATION_CNF"
    echo "relay-log-index=mysql-relay-bin.index" >> "$REPLICATION_CNF"
    echo "expire_logs_days=15" >> "$REPLICATION_CNF"
    echo "max_binlog_size=512M" >> "$REPLICATION_CNF"
    echo "Created $REPLICATION_CNF"
}

function replication_init_master(){
    replication_init_cnf
    replication_init_sql
    replication_init_user
    echo "server_id=1" >> "$REPLICATION_CNF"
    echo "SHOW MASTER STATUS;" >> "$REPLICATION_SQL"
    echo "SHOW SLAVE STATUS;" >> "$REPLICATION_SQL"
}

function replication_init_slave(){
    replication_init_cnf
    replication_init_sql
    replication_init_user
    sleep 20 # wait for master
    echo "server_id=$(node_number)" >> "$REPLICATION_CNF"
    echo "SELECT SLEEP(5);" >> "$REPLICATION_SQL"
    echo "START SLAVE;" >> "$REPLICATION_SQL"
    echo "SELECT SLEEP(5);" >> "$REPLICATION_SQL"
    echo "SHOW MASTER STATUS;" >> "$REPLICATION_SQL"
    echo "SHOW SLAVE STATUS;" >> "$REPLICATION_SQL"
}

function replication_init_xtrabackup(){
    REPLICATION_USERS_SQL="/etc/initdb.d/50-users.sql"
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'127.0.0.1' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'127.0.0.1';"  >> "$REPLICATION_USERS_SQL"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'localhost' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'localhost';" >> "$REPLICATION_USERS_SQL"
    source xtrabackup_cnf.sh
}

function main(){
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

