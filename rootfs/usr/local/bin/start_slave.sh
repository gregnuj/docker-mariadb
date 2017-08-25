#!/bin/bash

source mysql_common.sh

# Set 'DEBUG=1' environment variable to see detailed output for debugging
if [[ -n "$DEBUG" ]]; then
    set -x
fi

sleep 5;
echo "Starting slave replication"
mysql=( $(mysql_client) )
sql=( "STOP SLAVE;" )
sql+=( "CHANGE MASTER TO" )
sql+=( "MASTER_HOST='$(replication_master)'," )
sql+=( "MASTER_USER='$(replication_user)'," )
sql+=( "MASTER_PASSWORD='$(replication_password)'," )
sql+=( "MASTER_USE_GTID=current_pos," )
sql+=( "MASTER_PORT=3306," )
sql+=( "MASTER_CONNECT_RETRY=30;" ) 
sql+=( "START SLAVE;" )
sql+=( "SHOW MASTER STATUS\G;" ) 
sql+=( "SHOW SLAVE STATUS\G;" )
echo "${sql[@]}" | "${mysql[@]}"

