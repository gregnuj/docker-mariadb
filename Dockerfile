FROM mariadb:10.2

LABEL MAINTAINER="Greg Junge <gregnuj@gmail.com>"

RUN set -e \
    && apt-get update \
    && apt-get install -y \
    --no-install-recommends \
    --no-install-suggests \
    vim dnsutils curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/initdb.d  \
    && chown -R mysql:mysql /etc/mysql \
    && chown -R mysql:mysql /etc/initdb.d \
    && chown -R mysql:mysql /var/lib/mysql \
    && rm -rf /docker-entrypoint* \
    && sed -ie 's/docker-entrypoint-initdb.d/etc\/initdb.d/' /usr/local/bin/docker-entrypoint.sh 

# we expose all Cluster related Ports
# 3306: default MySQL/MariaDB listening port
# 4444: for State Snapshot Transfers
# 4567: Galera Cluster Replication
# 4568: Incremental State Transfer
EXPOSE 3306 4444 4567 4567/udp 4568

COPY rootfs/ /

ENTRYPOINT ["/usr/local/bin/mariadb-entrypoint.sh"]
CMD ["mysqld"]
