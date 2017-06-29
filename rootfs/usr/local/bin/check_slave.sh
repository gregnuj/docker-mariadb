#!/bin/bash -e

source mysql_common.sh

echo "SHOW SLAVE STATUS\G;" | ( $(mysql_client) ) 
