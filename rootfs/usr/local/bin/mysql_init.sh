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


function mysql_init_bootstrap(){
    # Galera primary component container
    if [ -f "$(grastate_dat)" ]; then 
       if [ -n "${SAFE_TO_BOOTSTRAP}" ]; then
           sed -i "s/safe_to_bootstrap:.*/safe_to_bootstrap: 1/" $(grastate_dat) 
       else
           sed -i "s/safe_to_bootstrap:.*/safe_to_bootstrap: 0/" $(grastate_dat)
       fi
    fi
}

function mysql_init_replication(){
    if [[ -z "${REPLICATION_PORT}" ]]; then
       REPLICATION_PORT=3306
    fi
    if [[ ! -z "${REPLICATION_MASTER}" ]]; then
        SERVER_ID="${SERVER_ID:="$(hostname -i | awk -F. '{print $NF}')"}"
        REPLICATION_USER="$(replication_user)"
        REPLICATION_PASSWORD="$(replication_password)"
        sql=( "STOP SLAVE;" )
        sql+=( "SET GLOBAL server_id=${SERVER_ID};" )
        sql+=( "SET GLOBAL replicate_ignore_db = 'mysql,information_schema,performance_schema';" )
        sql+=( "CHANGE MASTER TO" )
        sql+=( "MASTER_HOST='${REPLICATION_MASTER}'," )
        sql+=( "MASTER_USER='$(replication_user)'," )
        sql+=( "MASTER_PASSWORD='$(replication_password)'," )
        sql+=( "MASTER_USE_GTID=current_pos," )
        sql+=( "MASTER_PORT=${REPLICATION_PORT}," )
        sql+=( "MASTER_CONNECT_RETRY=30;" )
        sql+=( "START SLAVE;" )
        echo "${sql[@]}"
    fi
}

function mysql_init_file(){
    MYSQL_INIT_FILE="${MYSQL_INIT_FILE:="/etc/mysql/mysql_init_file.sql"}"
    echo "${MYSQL_INIT_FILE}"
}

function mysql_init_sql(){
    MYSQL_INIT_FILE="$(mysql_init_file)"
    : > ${MYSQL_INIT_FILE}
    if [[ ! -z "${REPLICATION_MASTER}" ]]; then
        echo "$(mysql_init_replication)" | sed -e 's/;/&\n/g' >> ${MYSQL_INIT_FILE}
    fi
}

function mysql_init_do(){
    if [[ ! -d "$(mysql_datadir)/mysql" ]]; then
        MYSQLD_INIT=${MYSQLD_INIT:=1}
    fi
    echo "${MYSQLD_INIT}"
}

function main(){
    if [[ ! -z "$(mysql_init_do)" ]]; then
        mysql_init_install
        mysql_init_start
        mysql_init_check 
        mysql_init_root 
        mysql_init_tz 
        mysql_init_database
        mysql_init_user
        mysql_init_replication_user
        mysql_init_scripts 
        mysql_shutdown
    fi
    mysql_init_sql;
    mysql_init_bootstrap;
}

main 

