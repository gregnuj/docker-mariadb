#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source xtrabackup_common.sh

cat <<-EOF > "$(replication_cnf)" 
[mysqld]
log-error=/dev/stderr
skip_name_resolve

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
binlog-format=row
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

wsrep_sst_method=$(wsrep_sst_method)
wsrep-sst-auth=$(wsrep_sst_auth)

wsrep-provider="/usr/lib/galera/libgalera_smm.so
wsrep_provider_options = "
      debug=${WSREP_DEBUG} 
      evs.suspect_timeout = PT30S;
      evs.inactive_timeout = PT1M;
      evs.install_timeout = PT1M;
      evs.keepalive_period = PT3S;
      evs.max_install_timeouts=10;
      evs.user_send_window=1024;
      evs.send_window=2048;
      gcs.fc_limit = 256;
      gcs.fc_factor = 0.99;
      gcs.fc_master_slave = YES;
      gcache.size=1G;
      gache.page_size=512M; 
      gcache.recover=yes;
      pc.recovery=true;
      pc.wait_prim=true;
      pc.wait_prim_timeout=PT300S;
      pc.weight=$(wsrep_pc_weight);
"
#     pc.npvo=true;

[sst]
progress=1
streamfmt=xbstream

EOF

echo Created "$(replication_cnf)"
echo "-------------------------------------------------------------------------"
grep -v "wsrep-sst-auth"  $(replication_cnf)
echo "-------------------------------------------------------------------------"

