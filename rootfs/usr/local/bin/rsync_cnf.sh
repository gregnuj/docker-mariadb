#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source galera_common.sh

cat <<-EOF > "$(replication_cnf)" 
[mysqld]
bind-address=0.0.0.0

# InnoDB http://galeracluster.com/documentation-webpages/configuration.html
default_storage_engine = InnoDB
innodb_autoinc_lock_mode=2
innodb-flush-log-at-trx-commit=0 
innodb-buffer-pool-size=122M	
#innodb_file_per_table=1
#innodb-flush-method=O_DIRECT
#innodb_locks_unsafe_for_binlog=1
#innodb-log-file-size=512M
#innodb-log-files-in-group=2

# Logs
binlog_format=ROW
log-bin=binlog
log-error = /var/log/mysql/mysql-error.log
slow-query-log = 1
slow-query-log-file = /var/log/mysql/mysql-slow.log

# Galera-related settings #
[galera]
wsrep_on=ON
#wsrep-node-name=$(wsrep_node_name)
wsrep_node_address=$(wsrep_node_address)
wsrep-cluster-name=$(wsrep_cluster_name)
wsrep-cluster-address=$(wsrep_cluster_address)
#wsrep-max-ws-size=1024K
wsrep_slave_threads=8

wsrep_sst_method=rsync
wsrep-sst-auth=$(wsrep_sst_auth)

wsrep-provider="/usr/lib/galera/libgalera_smm.so
wsrep_provider_options = "
      debug=${WSREP_DEBUG} 
"

EOF

echo Created "$(replication_cnf)"
echo "-------------------------------------------------------------------------"
grep -v "wsrep-sst-auth"  $(replication_cnf)
echo "-------------------------------------------------------------------------"

