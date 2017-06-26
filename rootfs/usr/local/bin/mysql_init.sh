#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source mysql_common.sh

declare MYSQLD=( $@ )

function mysql_init_install(){
    mkdir -p "$(mysql_datadir)"
    chown -R mysql:mysql "$(mysql_datadir)"
    mysql_install_db --user=mysql --datadir="$(mysql_datadir)" --rpm 
}

function mysql_init_start(){
    "${MYSQLD[@]}" --skip-networking --socket=/var/run/mysqld/mysqld.sock &
    PID="$!"
}

function mysql_init_client(){
    mysql=( mysql --protocol=socket -uroot -hlocalhost --socket=/var/run/mysqld/mysqld.sock )
    if [ ! -z "$MYSQLD_INIT_ROOT" ]; then
        mysql+=( -p"${MYSQLD_INIT_ROOT}" )
    fi
    echo "${mysql[@]}"
}

function mysql_init_check(){
    mysql=( $(mysql_init_client) )
    for i in {30..0}; do
        if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
            break
        fi
        echo 'MySQL init process in progress...'
        sleep 2
    done
    if [[ "$i" = "0" ]]; then
        echo >&2 'MySQL init process failed.'
        exit 1
    fi
}

function mysql_init_root(){
    mysql=( $(mysql_init_client) )
    sql=( "SET @@SESSION.SQL_LOG_BIN=0;" )
    sql+=( "DELETE FROM mysql.user ;" )
    sql+=( "CREATE USER 'root'@'%' IDENTIFIED BY '$(mysql_password root)' ;" )
    sql+=( "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;" )
    sql+=( "DROP DATABASE IF EXISTS test ;" )
    sql+=( "FLUSH PRIVILEGES ;" )
    echo "${sql[@]}" | "${mysql[@]}"
    MYSQLD_INIT_ROOT=1
}

function mysql_init_tz(){
    mysql=( $(mysql_client) )
    if [[ -z "$MYSQL_INITDB_SKIP_TZINFO" ]]; then
        # sed is for https://bugs.mysql.com/bug.php?id=20545
        mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
    fi
}

function mysql_init_database(){
    if [[ ! -z "$MYSQL_DATABASE" ]]; then
        MYSQL_DATABASE_SQL="/etc/initdb.d/10-database.sql"
        echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" >> "$MYSQL_DATABASE_SQL"
    fi
}

function mysql_init_user(){
    MYSQL_USERS_SQL="/etc/initdb.d/50-users.sql"
    SERVICE_NAME="${SERVICE_NAME:="$(service_name)"}"
    MYSQL_DATABASE="${MYSQL_DATABASE:="${SERVICE_NAME%-*}"}"
    MYSQL_USER="${MYSQL_USER:="${MYSQL_DATABASE}"}"
    MYSQL_PASSWORD="$(mysql_password $MYSQL_USER)"
    echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" >> "$MYSQL_USERS_SQL"
    echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" >> "$MYSQL_USERS_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$MYSQL_USERS_SQL"
    echo "Created user $MYSQL_USER"
}


function replication_init_user(){
    REPLICATION_USERS_SQL="/etc/initdb.d/50-users.sql"
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'%';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%';" >> "$REPLICATION_USERS_SQL"
    echo "GRANT LOCK TABLES ON *.* TO '${REPLICATION_USER}'@'%';"  >> "$REPLICATION_USERS_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$REPLICATION_USERS_SQL"
    echo "Created $REPLICATION_USERS_SQL"
}


function replication_init_cnf(){
    SERVER_ID="$1"
    REPLICATION_CNF="$(replication_cnf)"
    echo "[mariadb]" >> "$REPLICATION_CNF"
    echo "server_id=${SERVER_ID}" >> "$REPLICATION_CNF"
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
    replication_init_cnf 1
    
    REPLICATION_SQL="/etc/initdb.d/60-replication.sql"
    echo "SHOW MASTER STATUS;" >> "$REPLICATION_SQL"
    echo "SHOW SLAVE STATUS;" >> "$REPLICATION_SQL"
}

function replication_init_slave(){
    sleep 20 # wait for master
    replication_init_cnf $(node_number)

    REPLICATION_SQL="/etc/initdb.d/60-replication.sql"
    echo "CHANGE MASTER TO" >> "$REPLICATION_SQL"
    echo "MASTER_HOST='$(replication_master)'," >> "$REPLICATION_SQL"
    echo "MASTER_USER='$(replication_user)'," >> "$REPLICATION_SQL"
    echo "MASTER_PASSWORD='$(replication_password)'," >> "$REPLICATION_SQL"
    echo "MASTER_PORT=3306," >> "$REPLICATION_SQL"
    echo "MASTER_CONNECT_RETRY=30;" >> "$REPLICATION_SQL"
    echo "SELECT SLEEP(5);" >> "$REPLICATION_SQL"
    echo "START SLAVE;" >> "$REPLICATION_SQL"
    echo "SELECT SLEEP(5);" >> "$REPLICATION_SQL"
    echo "SHOW MASTER STATUS;" >> "$REPLICATION_SQL"
    echo "SHOW SLAVE STATUS;" >> "$REPLICATION_SQL"
    echo "Created $REPLICATION_SQL"
}

function replication_init_xtrabackup(){
    source xtrabackup_cnf.sh
}

function mysql_init_scripts(){
    mysql=( $(mysql_client) )
    for f in /etc/initdb.d/*; do
        case "$f" in
            *.sh)     echo "$0: running $f"; . "$f" ;;
            *.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
            *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
            *)        echo "$0: ignoring $f" ;;
         esac
         echo
    done
}

function main(){
    case "${REPLICATION_METHOD}" in
        xtrabackup*)
            GALERA_INIT=1
            mysql_init_user 
            mysql_init_database
            replication_init_xtrabackup
            ;;
        master)
            mysql_init_user 
            mysql_init_database
            replication_init_master
            ;;
        slave)
            replication_init_slave
            ;;
        *)
            mysql_init_user 
            mysql_init_database
            ;;
    esac
    # Set env MYSQLD_INIT to trigger setup 
    if [[ ! -d "$(mysql_datadir)/mysql" ]]; then
        MYSQLD_INIT=${MYSQLD_INIT:=1}
    fi
    if [[ ! -z "$MYSQLD_INIT" ]]; then
        mysql_init_install
        mysql_init_start
        mysql_init_check 
        mysql_init_root 
        mysql_init_tz 
        mysql_init_scripts 
        mysql_shutdown
    fi
}

main 

