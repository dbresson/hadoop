#!/usr/bin/env bash

CORE_SITE="/etc/hadoop/conf/core-site.xml"
HDFS_SITE="/etc/hadoop/conf/hdfs-site.xml"
LOG_DIR="/var/log/hadoop/hdfs"
PID_DIR="/var/run/hadoop/hdfs"

addConfig () {

    if [ $# -ne 3 ]; then
        echo "There should be 3 arguments to addConfig: <file-to-modify.xml>, <property>, <value>"
        echo "Given: $@"
        exit 1
    fi

    xmlstarlet ed -L -s "/configuration" -t elem -n propertyTMP -v "" \
     -s "/configuration/propertyTMP" -t elem -n name -v $2 \
     -s "/configuration/propertyTMP" -t elem -n value -v $3 \
     -r "/configuration/propertyTMP" -v "property" \
     $1
}

# Update core-site.xml
[ ! -z "$FS_DEFAULTFS" ] && addConfig $CORE_SITE "fs.defaultFS" "hdfs://${FS_DEFAULTFS}"
addConfig $CORE_SITE "fs.trash.interval" ${FS_TRASH_INTERVAL:=1440}
addConfig $CORE_SITE "fs.trash.checkpoint.interval" ${FS_TRASH_CHECKPOINT_INTERVAL:=0}
addConfig $CORE_SITE "ipc.client.connect.retry.interval" 4000
addConfig $CORE_SITE "ipc.client.connect.max.retries" 100

# Update hdfs-site.xml
addConfig $HDFS_SITE "dfs.permissions.superusergroup" "hadoop"
addConfig $HDFS_SITE "dfs.datanode.max.transfer.threads" 4096

: ${DFS_NAMESERVICES:?"DFS_NAMESERVICES is required."}
addConfig $HDFS_SITE "dfs.nameservices" $DFS_NAMESERVICES

# Create namenodes config
IFS=',' read -ra DFS_NAMESERVICE <<< "$DFS_NAMESERVICES"
for i in "${DFS_NAMESERVICE[@]}"; do

    addConfig $HDFS_SITE "dfs.ha.namenodes.${i}" "nn1,nn2"

    VAR=${i^^}_DFS_NAMENODE_RPC_ADDRESS_NN1
    : ${!VAR:?"${VAR} is required."}
    addConfig $HDFS_SITE "dfs.namenode.rpc-address.${i}.nn1" ${!VAR}

    VAR=${i^^}_DFS_NAMENODE_RPC_ADDRESS_NN2
    : ${!VAR:?"${VAR} is required."}
    addConfig $HDFS_SITE "dfs.namenode.rpc-address.${i}.nn2" ${!VAR}

    VAR=${i^^}_DFS_NAMENODE_HTTP_ADDRESS_NN1
    : ${!VAR:?"${VAR} is required."}
    addConfig $HDFS_SITE "dfs.namenode.http-address.${i}.nn1" ${!VAR}

    VAR=${i^^}_DFS_NAMENODE_HTTP_ADDRESS_NN2
    : ${!VAR:?"${VAR} is required."}
    addConfig $HDFS_SITE "dfs.namenode.http-address.${i}.nn2" ${!VAR}

    addConfig $HDFS_SITE "dfs.client.failover.proxy.provider.${i}" "org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider"
done

addConfig $HDFS_SITE "dfs.datanode.name.dir" ${DFS_DATANODE_NAME_DIR:="file:///var/lib/hadoop-hdfs/data"}
[ ! -z "$DFS_DATANODE_FSDATASET_VOLUME_CHOOSING_POLICY" ] && addConfig $HDFS_SITE "dfs.datanode.fsdataset.volume.choosing.policy" "org.apache.hadoop.hdfs.server.datanode.fsdataset.AvailableSpaceVolumeChoosingPolicy"
[ ! -z "$DFS_DATANODE_AVAILABLE_SPACE_VOLUME_CHOOSING_POLICY_BALANCED_SPACE_THRESHOLD" ] && addConfig $HDFS_SITE "dfs.datanode.available-space-volume-choosing-policy.balanced-space-threshold" $DFS_DATANODE_AVAILABLE_SPACE_VOLUME_CHOOSING_POLICY_BALANCED_SPACE_THRESHOLD
[ ! -z "$DFS_DATANODE_AVAILABLE_SPACE_VOLUME_CHOOSING_POLICY_BALANCED_SPACE_PREFRENCE_FRACTION" ] && addConfig $HDFS_SITE "dfs.datanode.available-space-volume-choosing-policy.balanced-space-preference-fraction" $DFS_DATANODE_AVAILABLE_SPACE_VOLUME_CHOOSING_POLICY_BALANCED_SPACE_PREFRENCE_FRACTION

# Create and set the data directories correctly
IFS=',' read -ra DFS_DATANODE_NAME_DIRS <<< "$DFS_DATANODE_NAME_DIR"
for i in "${DFS_DATANODE_NAME_DIRS[@]}"; do

    if [[ $i == "file:///"* ]]; then
        path=${i/"file://"/""}
        mkdir -p $path
        chown -R hdfs:hdfs $path
        chmod 700 $path
    fi
done

# Start the datanode
exec gosu hdfs hdfs --config /etc/hadoop/conf datanode