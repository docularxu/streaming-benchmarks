#!/bin/bash
# Copyright 2019, Linaro Inc.
# Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
set -o pipefail
set -o errtrace
set -o nounset
set -o errexit

LOAD=${LOAD:-10000}
TEST_TIME=${TEST_TIME:-120}
PARTITIONS=${PARTITIONS:-6}
N_KAFKA_FEEDERS=${N_KAFKA_FEEDERS:-6}
PROCESS_HOSTS=${PROCESS_HOSTS:-1}
PROCESS_CORES=${PROCESS_CORES:-56}

CONF_FILE=./conf/d05-multinode-Conf.yaml

REDIS_VERSION=${REDIS_VERSION:-"4.0.11"}
REDIS_DIR="redis-$REDIS_VERSION"
REDIS_SERVER="192.168.10.177"

KAFKA_DIR="/usr/lib/kafka"
FLINK_DIR="/usr/lib/flink"
KAFKA_HOST="d05-005"
ZK_HOST="d05-001"
ZK_PORT="2181"
ZK_CONNECTIONS="$ZK_HOST:$ZK_PORT"

TOPIC=${TOPIC:-"ad-events"}
LEIN=${LEIN:-"/home/guodong/bin/lein"}

# on which nodes run kafka producer load. This parameter is space separated
PRODUCER_NODES=${PRODUCER_NODES:-"d05-006 d05-003 d05-001"}
# on each of producer nodes, how many maximumly load process is allowed.
PRODUCER_NODES_CAP=( 12 12 12)

# to start load instances in named node
# $1: node name
# $2: number of load instances
start_load_local() {
   local command_string

   echo "starting "$2" load instances on node "$1
   # issue the command
   command_string="cd /home/guodong/yahoo-streaming-benchmarks-clone-001; ./sb5.sh START_LOAD_LOCAL "$2
   echo $command_string
   sshpass -f ~/.ssh/sshpassphrase ssh guodong@$1 $command_string
}

start_load() {
   local i=0
   local num_feeders=$N_KAFKA_FEEDERS

   # go through node list
   for node in $PRODUCER_NODES
   do
     # copy CONF_FILE to nodes
     sshpass -f ~/.ssh/sshpassphrase rsync $CONF_FILE guodong@$node:/home/guodong/yahoo-streaming-benchmarks-clone-001/$CONF_FILE
     # copy self to nodes
     sshpass -f ~/.ssh/sshpassphrase rsync sb5.sh guodong@$node:/home/guodong/yahoo-streaming-benchmarks-clone-001/sb5.sh
     if [ $num_feeders -gt ${PRODUCER_NODES_CAP[$i]} ]
     then
       # call start_load_local start max cap instances on this node
       start_load_local $node ${PRODUCER_NODES_CAP[$i]} 
     else
       # call start_load_local to start num_feeders instances on this node
       start_load_local $node $num_feeders
       break
     fi
     num_feeders=$(($num_feeders-${PRODUCER_NODES_CAP[$i]}))
     i=$(($i+1))
   done
}

stop_load() {
   # go through node list
   for node in $PRODUCER_NODES
   do
     # stop local on this $node
     echo "Stop load on node: "$node
     sshpass -f ~/.ssh/sshpassphrase ssh guodong@$node 'cd /home/guodong/yahoo-streaming-benchmarks-clone-001; ./sb5.sh STOP_LOAD_LOCAL'
   done
}

pid_match() {
   local VAL=`ps -aef | grep "$1" | grep -v grep | awk '{print $2}'`
   echo $VAL
}

delete_kafka_topic () {
  echo "Deleting $TOPIC ..."
  $KAFKA_DIR/bin/kafka-topics.sh  --zookeeper "$ZK_CONNECTIONS" --delete --topic $TOPIC
  $KAFKA_DIR/bin/zookeeper-shell.sh $ZK_HOST rmr /brokers/topics/$TOPIC
  $KAFKA_DIR/bin/zookeeper-shell.sh $ZK_HOST rmr /config/topics/$TOPIC
  $KAFKA_DIR/bin/zookeeper-shell.sh $ZK_HOST rmr /admin/delete_topics/$TOPIC
}

create_kafka_topic() {
    local count=`$KAFKA_DIR/bin/kafka-topics.sh --describe --zookeeper "$ZK_CONNECTIONS" --topic $TOPIC 2>/dev/null | grep -c $TOPIC`
    echo "enter  create_kafka_topic"
    if [[ "$count" = "0" ]];
    then
        echo "Kafka topic $TOPIC doesn't exist. Create it."
    else
        echo "Kafka topic $TOPIC already exists"
        echo "delete $TOPIC first, then create it"
        delete_kafka_topic
    fi
    echo "calling kafka-topics.sh --create"
    $KAFKA_DIR/bin/kafka-topics.sh --create --zookeeper "$ZK_CONNECTIONS" --replication-factor 1 --partitions $PARTITIONS --topic $TOPIC
    echo "calling kafka-topics.sh --describe"
    $KAFKA_DIR/bin/kafka-topics.sh --describe --zookeeper "$ZK_CONNECTIONS" --topic $TOPIC
}

start_if_needed() {
  local match="$1"
  shift
  local name="$1"
  shift
  local sleep_time="$1"
  shift
  local PID=`pid_match "$match"`

  if [[ "$PID" -ne "" ]];
  then
    echo "$name is already running..."
  else
    "$@" &
    sleep $sleep_time
  fi
}

stop_if_needed() {
  local match="$1"
  local name="$2"
  local PID=`pid_match "$match"`
  # if [[ "$PID" -ne "" ]];
  if ! [[ -z "$PID" ]];
  then
    kill $PID
    echo "Killed pid(s): $PID with name: $name"
    sleep 1
    local CHECK_AGAIN=`pid_match "$match"`
    if ! [[ -z "$CHECK_AGAIN" ]];
    then
      kill -9 $CHECK_AGAIN
    fi
  else
    echo "No $name instance found to stop"
  fi
}

run() {
  local OPERATION=$1
  echo "===================="
  echo "    $OPERATION"
  echo "===================="
# generate conf file
  if [ "GEN_CONF_FILE" = "$OPERATION" ];
  then
    echo 'kafka.brokers:' > $CONF_FILE
    echo '    - "'$KAFKA_HOST'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'zookeeper.servers:' >> $CONF_FILE
    echo '    - "'$ZK_HOST'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'kafka.port: 9092' >> $CONF_FILE
    echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
    echo 'redis.host: "'$REDIS_SERVER'"' >> $CONF_FILE
    echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
    echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
    echo 'process.hosts: '$PROCESS_HOSTS >> $CONF_FILE
    echo 'process.cores: '$PROCESS_CORES >> $CONF_FILE
    echo 'storm.workers: 1' >> $CONF_FILE
    echo 'storm.ackers: 2' >> $CONF_FILE
    echo 'spark.batchtime: 2000' >> $CONF_FILE
    cat $CONF_FILE
    echo "... done"
# start zk
  elif [ "START_ZK" = "$OPERATION" ];
  then
    echo "nothing to do"
# start redis
  elif [ "START_REDIS" = "$OPERATION" ];
  then
    # start_if_needed redis-server Redis 1 "$REDIS_DIR/src/redis-server" $REDIS_DIR/redis.conf
    # remote Redis server
    sshpass -f ~/.ssh/sshpassphrase ssh guodong@d05-002 '/home/guodong/bin/start-redis.sh' &
    sleep 3
# start campaigns
  elif [ "START_CAMPAIGNS" = "$OPERATION" ];
  then
    cd data
    $LEIN run -n --configPath ../$CONF_FILE
    cd ..
# start kafka
  elif [ "START_KAFKA" = "$OPERATION" ];
  then
    create_kafka_topic
# start flink
  elif [ "START_FLINK" = "$OPERATION" ];
  then
    echo "nothing to do"
# start flink processing
  elif [ "START_FLINK_PROCESSING" = "$OPERATION" ];
  then
    "/usr/bin/flink" run ./flink-benchmarks/target/flink-benchmarks-0.1.0.jar --confPath $CONF_FILE &
    sleep 3
# start load
  elif [ "START_LOAD" = "$OPERATION" ];
  then
    start_load
  elif [ "START_LOAD_LOCAL" = "$OPERATION" ];
  then
    num_of_instance=$2
    shift
    for i in `seq $num_of_instance`
    do
      cd data
      $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > /dev/null &
      cd ..
    done
# sleep TEST_TIME
  elif [ "SLEEP_SECONDS" = "$OPERATION" ];
  then
    sleep $TEST_TIME
# stop load
  elif [ "STOP_LOAD_LOCAL" = "$OPERATION" ];
  then
    stop_if_needed leiningen.core.main "Load Generation"
  elif [ "STOP_LOAD" = "$OPERATION" ];
  then
    stop_load
    sleep 10
    # summarize & report
    cd data
    $LEIN run -g --configPath ../$CONF_FILE || true
    cd ..
# stop flink processing
  elif [ "STOP_FLINK_PROCESSING" = "$OPERATION" ];
  then
    FLINK_ID=`"$FLINK_DIR/bin/flink" list | grep 'Flink Streaming Job' | awk '{print $4}'; true`
    if [ "$FLINK_ID" == "" ];
	then
	  echo "Could not find streaming job to kill"
    else
      "$FLINK_DIR/bin/flink" cancel $FLINK_ID
      sleep 3
    fi
# stop flink
  elif [ "STOP_FLINK" = "$OPERATION" ];
  then
    echo "nothing to do"
# stop kafka
  elif [ "STOP_KAFKA" = "$OPERATION" ];
  then
    echo "nothing to do"
    # stop_if_needed kafka\.Kafka Kafka
    # rm -rf /tmp/kafka-logs/
# stop redis
  elif [ "STOP_REDIS" = "$OPERATION" ];
  then
    # stop_if_needed redis-server Redis
    # rm -f dump.rdb
    # remote redis server
    sshpass -f ~/.ssh/sshpassphrase ssh guodong@d05-002 '/home/guodong/bin/stop-redis.sh'
# stop zk
  elif [ "STOP_ZK" = "$OPERATION" ];
  then
    echo "nothing to do"
  else
    echo "UNKNOWN Operation '$OPERATION'"
  fi

}

if [ $# -lt 1 ];
then
  echo "Usage: $0 operation" 
else
  while [ $# -gt 0 ];
  do
    if [ $1 == "START_LOAD_LOCAL" ]
    then
      run "$1" "$2"
      shift
    else
      run "$1"
    fi  
    shift
  done
fi
