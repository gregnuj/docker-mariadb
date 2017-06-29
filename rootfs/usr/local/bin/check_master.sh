#!/bin/bash -e

source mysql_common.sh

echo "SHOW MASTER STATUS\G;" | ( $(mysql_client) ) 
