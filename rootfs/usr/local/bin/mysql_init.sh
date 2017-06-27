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
    echo "Creating root user"
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
    echo "Setting timezone"
    mysql=( $(mysql_client) )
    if [[ -z "$MYSQL_INITDB_SKIP_TZINFO" ]]; then
        # sed is for https://bugs.mysql.com/bug.php?id=20545
        mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
    fi
}

function mysql_init_database(){
    if [[ ! -z "$MYSQL_DATABASE" ]]; then
        echo "Creating database $MYSQL_DATABASE"
        mysql=( $(mysql_client) )
        MYSQL_DATABASE_SQL="/etc/initdb.d/10-database.sql"
        echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}" 
    fi
}

function mysql_init_users(){
    case "${REPLICATION_METHOD}" in
        master)
            mysql_init_user
            mysql_init_replication_user
            ;;
        slave)
            mysql_init_replication_user
            ;;
        *)
            mysql_init_user
            ;;
    esac
}

function mysql_init_user(){
    mysql=( $(mysql_client) )
    MYSQL_USER="${MYSQL_USER:="${MYSQL_DATABASE}"}"
    MYSQL_PASSWORD="$(mysql_password $MYSQL_USER)"
    echo "Creating user $MYSQL_USER"
    sql=( "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" )
    [[ -z "${MYSQL_DATABASE}" ]] || sql+=( "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';" )
    sql+=( "FLUSH PRIVILEGES;" )
    echo "${sql[@]}" | "${mysql[@]}"
}

function mysql_init_replication_user(){
    mysql=( $(mysql_client) )
    REPLICATION_USER="$(replication_user)"
    REPLICATION_PASSWORD="$(replication_password)"
    echo "Creating mysql user $REPLICATION_USER"
    sql=( "CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';" )
    sql+=( "GRANT REPLICATION CLIENT ON *.* TO '${REPLICATION_USER}'@'%';" )
    sql+=( "GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%';" )
    sql+=( "GRANT LOCK TABLES ON *.* TO '${REPLICATION_USER}'@'%';" )
    sql+=( 'FLUSH PRIVILEGES ;' )
    echo "${sql[@]}" | "${mysql[@]}"
}


function mysql_init_replication(){
    case "${REPLICATION_METHOD}" in
        xtrabackup*)
            GALERA_INIT=1
            mysql_init_xtrabackup_cnf
            ;;
        master)
            MASTER_INIT=1
            mysql_init_replication_cnf 
            ;;
        slave)
            SLAVE_INIT=1
            mysql_init_replication_cnf 
            ;;
    esac
}

function mysql_init_xtrabackup_cnf(){
    source xtrabackup_cnf.sh
}

function mysql_init_replication_cnf(){
    REPLICATION_CNF="$(replication_cnf)"
    echo "Creating $REPLICATION_CNF"
    SERVER_ID="$(hostname -i | awk '{print $1}' | awk -F. '{print $4}')"
    echo "[mariadb]" >> "$REPLICATION_CNF"
    echo "server_id=${SERVER_ID}" >> "$REPLICATION_CNF"
    echo "skip-name-resolve=0" >> "$REPLICATION_CNF"
    echo "log-bin=mysql-bin" >> "$REPLICATION_CNF"
    echo "binlog-do-db=${APP_NAME}" >> "$REPLICATION_CNF"
    echo "relay-log=mysql-relay-bin" >> "$REPLICATION_CNF"
    echo "relay-log-index=mysql-relay-bin.index" >> "$REPLICATION_CNF"
    echo "expire_logs_days=15" >> "$REPLICATION_CNF"
    echo "max_binlog_size=512M" >> "$REPLICATION_CNF"
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

    # Set env MYSQLD_INIT to trigger setup 
    if [[ ! -d "$(mysql_datadir)/mysql" ]]; then
        MYSQLD_INIT=${MYSQLD_INIT:=1}
    fi

    if [[ ! -z "$MYSQLD_INIT" ]]; then
        mysql_init_replication
        mysql_init_install
        mysql_init_start
        mysql_init_check 
        mysql_init_root 
        mysql_init_tz 
        mysql_init_database
        mysql_init_users
        mysql_init_scripts 
        mysql_shutdown
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
            set -- "$@" "--wsrep-new-cluster"
        fi
    fi

    if [[ ! -z "${SLAVE_INIT}" ]]; then
       slave_start.sh &
    fi
}

main 

