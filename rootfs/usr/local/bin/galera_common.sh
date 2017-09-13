#!/bin/bash -e

[[ -z "$DEBUG" ]] || set -x

source swarm_common.sh
source mysql_common.sh

declare CLUSTER_UUID="${CLUSTER_UUID:="00000000-0000-0000-0000-000000000000"}"
declare CLUSTER_SEQNO="${CLUSTER_SEQNO:="-1"}"
declare CLUSTER_STB="${CLUSTER_STB:="0"}"

# Defaults to fqdn
function wsrep_node_name(){
    WSREP_NODE_NAME="${WSREP_NODE_NAME:="$(fqdn)"}"
    echo "${WSREP_NODE_NAME}"
}

# Defaults to  nod_address
function wsrep_node_address(){
    WSREP_NODE_ADDRESS="${WSREP_NODE_ADDRESS:="$(node_address)"}"
    echo "${WSREP_NODE_ADDRESS}"
}

# Defaults to servicename-cluster
function wsrep_cluster_name(){
    WSREP_CLUSTER_NAME="${WSREP_CLUSTER_NAME:="$(service_name)-cluster"}"
    echo "${WSREP_CLUSTER_NAME}"
}

# Defaults to 1
function wsrep_cluster_minimum(){
    WSREP_CLUSTER_MINIMUM="${WSREP_CLUSTER_MINIMUM:="1"}"
    echo $((WSREP_CLUSTER_MINIMUM))
}

# Built from cluster members
function wsrep_cluster_address(){
    WSREP_CLUSTER_PORT=$(wsrep_cluster_port)
    WSREP_CLUSTER_ADDRESS="${WSREP_CLUSTER_ADDRESS:="$(echo "$(wsrep_cluster_members)" | sed -e 's/^/gcomm:\/\//' -e "s/,/:${WSREP_CLUSTER_PORT},/g" -e "s/$/:${WSREP_CLUSTER_PORT}/")"}"
    #WSREP_CLUSTER_ADDRESS="${WSREP_CLUSTER_ADDRESS:="gcomm://$(service_name):$(wsrep_cluster_port)"}"
    echo "${WSREP_CLUSTER_ADDRESS}"
}

# Defaults to 4567
function wsrep_cluster_port(){
    WSREP_CLUSTER_PORT="${WSREP_CLUSTER_PORT:="4567"}"
    echo "${WSREP_CLUSTER_PORT}"
}

# discovered from docker_info.SERVICE_MEMBERS using CLUSTER_MINIMUM 
function wsrep_cluster_members(){
    WSREP_CLUSTER_MINIMUM=$(wsrep_cluster_minimum)
    while [[ -z "${WSREP_CLUSTER_MEMBERS}" ]]; do
       SERVICE_MEMBERS="$(service_members)"
       COUNT="$(service_count)"
       echo "Found ($COUNT) members in ${SERVICE_NAME} ($SERVICE_MEMBERS)" >&2
       if [[ $COUNT -lt $(($WSREP_CLUSTER_MINIMUM)) ]]; then
           echo "Waiting for at least $WSREP_CLUSTER_MINIMUM IP addresses to resolve..." >&2
           SLEEPS=$((SLEEPS + 1))
           sleep 3
       else
           WSREP_CLUSTER_MEMBERS="$SERVICE_MEMBERS"
       fi

       # After 90 seconds reduce SERVICE_ADDRESS_MINIMUM
       if [[ $SLEEPS -ge 30 ]]; then
          SLEEPS=0
          export WSREP_CLUSTER_MINIMUM=$((WSREP_CLUSTER_MINIMUM - 1))
          echo "Reducing WSREP_CLUSTER_MINIMUM to $WSREP_CLUSTER_MINIMUM" >&2
       fi
       if [[ $WSREP_CLUSTER_MINIMUM -lt 1 ]]; then
          echo "Something is wrong using service name as members"
	  WSREP_CLUSTER_MEMBERS="${SERVICE_NAME}"
       fi
    done
    echo "${WSREP_CLUSTER_MEMBERS}"
}

# Defaults to lowest ip in Cluster members
function wsrep_pc_address(){
    if [[ -z "${WSREP_PC_ADDRESS}" ]]; then
        WSREP_PC_ADDRESS=$(echo "$(wsrep_cluster_members)" | cut -d ',' -f 1 )
    fi
    echo "${WSREP_PC_ADDRESS}"
}

# Defaults 
function wsrep_pc_weight(){
    WSREP_CLUSTER_MINIMUM="$(wsrep_cluster_minimum)"
    if [[ -z "${WSREP_PC_WEIGHT}" ]]; then
        WSREP_PC_WEIGHT=$((WSREP_CLUSTER_MINIMUM/2-1))
    fi
    if [[ ! -z "$(is_primary_component)" ]]; then
        WSREP_PC_WEIGHT=$((WSREP_PC_WEIGHT+2))
    fi
    [ $WSREP_PC_WEIGHT -gt 0 ] || WSREP_PC_WEIGHT=1
    echo "$WSREP_PC_WEIGHT"
}

#
function wsrep_sst_method(){
    WSREP_SST_METHOD="${WSREP_SST_METHOD:="rsync"}"
    echo "${WSREP_SST_METHOD}"
}

#
function wsrep_sst_auth(){
    WSREP_SST_AUTH="${WSREP_SST_AUTH:="$(replication_user):$(replication_password)"}"
    echo "${WSREP_SST_AUTH}"
}

# This is primary
function is_primary_component(){
    if [[ "$(wsrep_pc_address)" == $(wsrep_node_address) ]]; then
        echo "true"
    fi
}

# Defaults to /var/lib/mysql/grastate.dat
function grastate_dat(){
    GRASTATE_DAT="${GRASTATE_DAT:="$(mysql_datadir)/grastate.dat"}"
    if [[ -f "$GRASTATE_DAT" ]]; then
        CLUSTER_UUID="$(awk '/^uuid:/{print $2}' $GRASTATE_DAT)"
        CLUSTER_STB="$(awk '/^safe_to_bootstrap:/{print $2}' $GRASTATE_DAT)"
        CLUSTER_SEQNO="$(awk '/^seqno:/{print $2}' $GRASTATE_DAT)"
    fi
    echo "${GRASTATE_DAT}"
}

function cluster_position(){
    GRASTATE_DAT="$(grastate_dat)"
    if [[ "$CLUSTER_UUID" == '00000000-0000-0000-0000-000000000000' ]]; then
        CLUSTER_POSITION=""
    #elif [[ "$CLUSTER_SEQNO" == "-1" ]]; then
    #    CLUSTER_POSITION=""
    else
    	CLUSTER_POSITION="$(cluster_uuid):$(cluster_seqno)"
    fi
    echo "$CLUSTER_POSITION" 
}

function cluster_seqno(){
    if [[ -z "${CLUSTER_SEQNO}" ]]; then :
        GRASTATE_DAT="$(grastate_dat)"
    fi
    echo "$CLUSTER_SEQNO"
}

function cluster_uuid(){
    if [[ -z "${CLUSTER_UUID}" ]]; then :
        GRASTATE_DAT="$(grastate_dat)"
    fi
    echo "$CLUSTER_UUID"
}

function cluster_stb(){
    if [[ -z "${CLUSTER_STB}" ]]; then 
        GRASTATE_DAT="$(grastate_dat)"
    fi
    echo "$CLUSTER_STB"
}


function main(){
    case "$1" in
        -a|--address)
            echo "$(wsrep_cluster_address)"
            ;;
        --auth)
            echo "$(wsrep_sst_auth)"
            ;;
        -m|--members)
            echo "$(wsrep_cluster_members)"
            ;;
        --method)
            echo "$(wsrep__sst_method)"
            ;;
        --minimum)
            echo "$(wsrep_cluster_minimum)"
            ;;
        -n|--name)
            echo "$(wsrep_cluster_name)"
            ;;
        -p|--primary)
            echo "$(wsrep_primary_component)"
            ;;
        -w|--weight)
            echo "$(wsrep_pc_weight)"
            ;;
    esac
}

main "$@"


