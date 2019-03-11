#!/bin/bash
# Copyright 2019, Linaro Inc.
# Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
set -o pipefail
set -o errtrace
set -o nounset
set -o errexit

REDIS_VERSION=${REDIS_VERSION:-"4.0.11"}
REDIS_DIR="redis-$REDIS_VERSION"

KAFKA_DIR="/usr/lib/kafka"
FLINK_DIR="/usr/lib/flink"
ZK_HOST="d05-001"
ZK_PORT="2181"
ZK_CONNECTIONS="$ZK_HOST:$ZK_PORT"

TOPIC=${TOPIC:-"ad-events"}
PARTITIONS=${PARTITIONS:-1}
LOAD=${LOAD:-1000}
CONF_FILE=./conf/d05-multinode-Conf.yaml
TEST_TIME=${TEST_TIME:-240}
LEIN=${LEIN:-lein}

pid_match() {
   local VAL=`ps -aef | grep "$1" | grep -v grep | awk '{print $2}'`
   echo $VAL
}

create_kafka_topic() {
    local count=`$KAFKA_DIR/bin/kafka-topics.sh --describe --zookeeper "$ZK_CONNECTIONS" --topic $TOPIC 2>/dev/null | grep -c $TOPIC`
    if [[ "$count" = "0" ]];
    then
        $KAFKA_DIR/bin/kafka-topics.sh --create --zookeeper "$ZK_CONNECTIONS" --replication-factor 1 --partitions $PARTITIONS --topic $TOPIC
    else
        echo "Kafka topic $TOPIC already exists"
    fi
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
# start zk
  if [ "START_ZK" = "$OPERATION" ];
  then
    echo "nothing to do"
# start redis
  elif [ "START_REDIS" = "$OPERATION" ];
  then
    start_if_needed redis-server Redis 1 "$REDIS_DIR/src/redis-server"
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
    "$FLINK_DIR/bin/flink" run ./flink-benchmarks/target/flink-benchmarks-0.1.0.jar --confPath $CONF_FILE &
    sleep 3
# start load
  elif [ "START_LOAD" = "$OPERATION" ];
  then
    cd data
    # instance 1
    start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > ~/t.t
    # instance 2
    $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > ~/t.t2 &
    sleep 1
    $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > ~/t.t3 &
    sleep 1
    $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > ~/t.t4 &
    sleep 1
    $LEIN run -r -t $LOAD --configPath ../$CONF_FILE > ~/t.t5 &
    sleep 1
    cd ..
# sleep TEST_TIME
  elif [ "SLEEP_SECONDS" = "$OPERATION" ];
  then
    sleep $TEST_TIME
# stop load
  elif [ "STOP_LOAD" = "$OPERATION" ];
  then
    stop_if_needed leiningen.core.main "Load Generation"
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
    stop_if_needed redis-server Redis
    rm -f dump.rdb
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
    run "$1"
    shift
  done
fi
