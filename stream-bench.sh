#!/usr/bin/bash
# Copyright 2015, Yahoo Inc.
# Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
set -o pipefail
set -o errtrace
set -o nounset
set -o errexit

LEIN=${LEIN:-lein}
MVN=${MVN:-mvn}
GIT=${GIT:-git}
MAKE=${MAKE:-make}

KAFKA_VERSION=${KAFKA_VERSION:-"0.8.2.1"}
REDIS_VERSION=${REDIS_VERSION:-"4.0.11"}
SCALA_BIN_VERSION=${SCALA_BIN_VERSION:-"2.11"}
SCALA_SUB_VERSION=${SCALA_SUB_VERSION:-"12"}
STORM_VERSION=${STORM_VERSION:-"1.2.2"}
FLINK_VERSION=${FLINK_VERSION:-"1.6.0"}
SPARK_VERSION=${SPARK_VERSION:-"2.3.1"}
#APEX_VERSION=${APEX_VERSION:-"3.4.0"}

STORM_DIR="apache-storm-$STORM_VERSION"
REDIS_DIR="redis-$REDIS_VERSION"
KAFKA_DIR="kafka_$SCALA_BIN_VERSION-$KAFKA_VERSION"
FLINK_DIR="flink-$FLINK_VERSION"
SPARK_DIR="spark-$SPARK_VERSION-bin-hadoop2.7"
#APEX_DIR="apex-$APEX_VERSION"

#Get one of the closet apache mirrors
APACHE_MIRROR=$"https://archive.apache.org/dist"

PROJECT_DIR="/var/scratch/ddps2103/streaming-benchmarks-master/"
#FLINK_NODES="node117.ib.cluster node118.ib.cluster"
FLINK_NODES="node301.ib.cluster node302.ib.cluster node303.ib.cluster node304.ib.cluster"
REDIS_NODE="node310.ib.cluster"
KAFKA_NODES="node305.ib.cluster node306.ib.cluster node307.ib.cluster node308.ib.cluster"
SPARK_MASTER=""
SPARK_SLAVES=""
ZK_HOST="node310.ib.cluster"
REDUCED_LOAD_HOST="node309.ib.cluster"
SELF_ID=$(hostname | grep -P '\d+' --only-matching)
NUM_HOSTS=4
NUM_PROCS=1
NUM_RUNS=55


#for spark run must 

ZK_PORT="2181"
ZK_CONNECTIONS="$ZK_HOST:$ZK_PORT"
TOPIC=${TOPIC:-"ad-events"}
PARTITIONS=${PARTITIONS:-200}
LOAD=${LOAD:-10000}
LOAD_REDUCED=${LOAD:-1000}
#CONF_FILE=./conf/localConf.yaml
CONF_FILE=./conf/benchmarkConf.yaml
TEST_TIME=${TEST_TIME:-120}
REDUCED_TEST_TIME=${REDUCED_TEST_TIME:-40}




pid_match() {
   local VAL=`ps -aef | grep "$1" | grep -v grep | awk '{print $2}'`
   echo $VAL
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
  if [[ "$PID" -ne "" ]];
  then
    kill "$PID"
    sleep 1
    local CHECK_AGAIN=`pid_match "$match"`
    if [[ "$CHECK_AGAIN" -ne "" ]];
    then
      kill -9 "$CHECK_AGAIN"
    fi
  else
    echo "No $name instance found to stop"
  fi
}

fetch_untar_file() {
  local FILE="download-cache/$1"
  local URL=$2
  if [[ -e "$FILE" ]];
  then
    echo "Using cached File $FILE"
  else
	mkdir -p download-cache/
    WGET=`whereis wget`
    CURL=`whereis curl`
    if [ -n "$WGET" ];
    then
      wget -O "$FILE" "$URL"
    elif [ -n "$CURL" ];
    then
      curl -o "$FILE" "$URL"
    else
      echo "Please install curl or wget to continue.";
      exit 1
    fi
  fi
  tar -xzvf "$FILE"
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




run() {
  OPERATION=$1
  if [ "SETUP_FLINK" = "$OPERATION" ];
  then
    echo 'kafka.brokers:' > $CONF_FILE
    kafka_brokers=$(getent hosts $KAFKA_NODES | awk '{ print $1}' | paste -sd " " -)
    echo '    - "'$kafka_brokers'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'zookeeper.servers:' >> $CONF_FILE
    zookeeper_host=$(getent hosts $ZK_HOST | awk '{ print $1}' | paste -sd " " -)
    echo '    - "'$zookeeper_host'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'kafka.port: 9092' >> $CONF_FILE
    echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
    redis_host=$(getent hosts $REDIS_NODE | awk '{ print $1}')
    echo 'redis.host: "'$redis_host'"' >> $CONF_FILE
    echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
    echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
    echo 'process.hosts: '$NUM_HOSTS >> $CONF_FILE
    echo 'process.cores: '$NUM_PROCS >> $CONF_FILE
  #	echo 'storm.workers: 1' >> $CONF_FILE
  #	echo 'storm.ackers: 2' >> $CONF_FILE
    echo 'spark.batchtime: 2000' >> $CONF_FILE
    
    # FLINK SETTINGS
    cp '../conf/flink_conf/flink-conf.yaml' $FLINK_DIR/conf/flink-conf.yaml
    echo 'jobmanager.rpc.address: '$redis_host >> $FLINK_DIR/conf/flink-conf.yaml
    echo 'jobmanager.heap.size: 1024m' >> $FLINK_DIR/conf/flink-conf.yaml
    echo 'taskmanager.heap.size: 4096m' >> $FLINK_DIR/conf/flink-conf.yaml
    echo 'taskmanager.numberOfTaskSlots: '1 >> $FLINK_DIR/conf/flink-conf.yaml
    echo 'jobmanager.web.address: 0.0.0.0' >> $FLINK_DIR/conf/flink-conf.yaml
    echo 'rest.port: 13345' >> $FLINK_DIR/conf/flink-conf.yaml
    
    echo "$redis_host:13345" > $FLINK_DIR/conf/masters
    echo -n > $FLINK_DIR/conf/slaves
    for worker in $FLINK_NODES
    do
      worker_host=$(getent hosts $worker | awk '{ print $1}')
      for ((i = 0 ; i < $NUM_PROCS ; i++)); do
        echo $worker_host >> $FLINK_DIR/conf/slaves
      done
    done
  
  elif [ "SETUP" = "$OPERATION" ];
  then
    $GIT clean -fd

    echo 'kafka.brokers:' > $CONF_FILE
    echo '    - "localhost"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'zookeeper.servers:' >> $CONF_FILE
    echo '    - "'$ZK_HOST'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'kafka.port: 9092' >> $CONF_FILE
    echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
    echo 'redis.host: "localhost"' >> $CONF_FILE
    echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
    echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
    echo 'process.hosts: 1' >> $CONF_FILE
    echo 'process.cores: 4' >> $CONF_FILE
  #	echo 'storm.workers: 1' >> $CONF_FILE
  #	echo 'storm.ackers: 2' >> $CONF_FILE
    echo 'spark.batchtime: 2000' >> $CONF_FILE
	
    $MVN clean install -Dspark.version="$SPARK_VERSION" -Dkafka.version="$KAFKA_VERSION" -Dflink.version="$FLINK_VERSION" -Dstorm.version="$STORM_VERSION" -Dscala.binary.version="$SCALA_BIN_VERSION" -Dscala.version="$SCALA_BIN_VERSION.$SCALA_SUB_VERSION" 

#-Dapex.version="$APEX_VERSION"

    #Fetch and build Redis
    REDIS_FILE="$REDIS_DIR.tar.gz"
    fetch_untar_file "$REDIS_FILE" "http://download.redis.io/releases/$REDIS_FILE"

    cd $REDIS_DIR
    $MAKE
    cd ..

    #Fetch Apex
#    APEX_FILE="$APEX_DIR.tgz.gz"
#    fetch_untar_file "$APEX_FILE" "$APACHE_MIRROR/apex/apache-apex-core-$APEX_VERSION/apex-$APEX_VERSION-source-release.tar.gz"
#    cd $APEX_DIR
#    $MVN clean install -DskipTests
#    cd ..

    #Fetch Kafka
    KAFKA_FILE="$KAFKA_DIR.tgz"
    fetch_untar_file "$KAFKA_FILE" "$APACHE_MIRROR/kafka/$KAFKA_VERSION/$KAFKA_FILE"

    #Fetch Storm
    STORM_FILE="$STORM_DIR.tar.gz"
    fetch_untar_file "$STORM_FILE" "$APACHE_MIRROR/storm/$STORM_DIR/$STORM_FILE"

    #Fetch Flink
    FLINK_FILE="$FLINK_DIR-bin-hadoop27-scala_${SCALA_BIN_VERSION}.tgz"
    fetch_untar_file "$FLINK_FILE" "$APACHE_MIRROR/flink/flink-$FLINK_VERSION/$FLINK_FILE"

    #Fetch Spark
    SPARK_FILE="$SPARK_DIR.tgz"
    fetch_untar_file "$SPARK_FILE" "$APACHE_MIRROR/spark/spark-$SPARK_VERSION/$SPARK_FILE"

 elif [ "SETUP_SPARK" = "$OPERATION" ];
  then
    #$GIT clean -fd
    echo 'Start Setup Spark'
    echo 'kafka.brokers:' > $CONF_FILE
    echo 'try 2'
    kafka_brokers=$(getent hosts $KAFKA_NODES | awk '{ print $1}' | paste -sd " " -)
    #kafka_brokers = 'node55.ib.cluster'
    echo '    - "'$kafka_brokers'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo "here"
    echo 'zookeeper.servers:' >> $CONF_FILE
    zookeeper_host=$(getent hosts $ZK_HOST | awk '{ print $1}' | paste -sd " " -)
    echo '    - "'$zookeeper_host'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'kafka.port: 9092' >> $CONF_FILE
    echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
    redis_host=$(getent hosts $REDIS_NODE | awk '{ print $1}')
    echo 'redis.host: "'$redis_host'"' >> $CONF_FILE
    echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
    echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
    echo 'process.hosts: '$NUM_HOSTS >> $CONF_FILE
    echo 'process.cores: '$NUM_PROCS >> $CONF_FILE
  #	echo 'storm.workers: 1' >> $CONF_FILE
  #	echo 'storm.ackers: 2' >> $CONF_FILE
    echo 'spark.batchtime: 2000' >> $CONF_FILE
    echo 'here 2'

    #SPARK SETUP
    truncate -s 0 $SPARK_DIR/conf/slaves
    truncate -s 0 $SPARK_DIR/conf/spark-env.sh

    echo "SPARK_MASTER_HOST=\"$SPARK_MASTER\"" >> $SPARK_DIR/conf/spark-env.sh

    echo -n > $SPARK_DIR/conf/slaves
    for worker in $SPARK_SLAVES
    do
      worker_host=$(getent hosts $worker | awk '{ print $1}')
      for ((i = 0 ; i < $NUM_PROCS ; i++)); do
        echo $worker_host >> $SPARK_DIR/conf/slaves
      done
    done
    
    cp $SPARK_DIR/conf/spark-defaults.conf.template $SPARK_DIR/conf/spark-defaults.conf
    echo "spark.master                     spark://$SPARK_MASTER:7077" >> $SPARK_DIR/conf/spark-defaults.conf
    
    
    #for node in $SPARK_SLAVES; do
    #  echo $node >> $SPARK_DIR/conf/slaves
    #done

    echo 'here 3'
    

    wait

  
  elif [ "SETUP" = "$OPERATION" ];
  then
    $GIT clean -fd

    echo 'kafka.brokers:' > $CONF_FILE
    echo '    - "localhost"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'zookeeper.servers:' >> $CONF_FILE
    echo '    - "'$ZK_HOST'"' >> $CONF_FILE
    echo >> $CONF_FILE
    echo 'kafka.port: 9092' >> $CONF_FILE
    echo 'zookeeper.port: '$ZK_PORT >> $CONF_FILE
    echo 'redis.host: "localhost"' >> $CONF_FILE
    echo 'kafka.topic: "'$TOPIC'"' >> $CONF_FILE
    echo 'kafka.partitions: '$PARTITIONS >> $CONF_FILE
    echo 'process.hosts: 1' >> $CONF_FILE
    echo 'process.cores: 4' >> $CONF_FILE
  #	echo 'storm.workers: 1' >> $CONF_FILE
  #	echo 'storm.ackers: 2' >> $CONF_FILE
    echo 'spark.batchtime: 2000' >> $CONF_FILE
	
    $MVN clean install -Dspark.version="$SPARK_VERSION" -Dkafka.version="$KAFKA_VERSION" -Dflink.version="$FLINK_VERSION" -Dstorm.version="$STORM_VERSION" -Dscala.binary.version="$SCALA_BIN_VERSION" -Dscala.version="$SCALA_BIN_VERSION.$SCALA_SUB_VERSION" 

#-Dapex.version="$APEX_VERSION"

    #Fetch and build Redis
    REDIS_FILE="$REDIS_DIR.tar.gz"
    fetch_untar_file "$REDIS_FILE" "http://download.redis.io/releases/$REDIS_FILE"

    cd $REDIS_DIR
    $MAKE
    cd ..

    #Fetch Apex
#    APEX_FILE="$APEX_DIR.tgz.gz"
#    fetch_untar_file "$APEX_FILE" "$APACHE_MIRROR/apex/apache-apex-core-$APEX_VERSION/apex-$APEX_VERSION-source-release.tar.gz"
#    cd $APEX_DIR
#    $MVN clean install -DskipTests
#    cd ..

    #Fetch Kafka
    KAFKA_FILE="$KAFKA_DIR.tgz"
    fetch_untar_file "$KAFKA_FILE" "$APACHE_MIRROR/kafka/$KAFKA_VERSION/$KAFKA_FILE"

    #Fetch Storm
    STORM_FILE="$STORM_DIR.tar.gz"
    fetch_untar_file "$STORM_FILE" "$APACHE_MIRROR/storm/$STORM_DIR/$STORM_FILE"

    #Fetch Flink
    FLINK_FILE="$FLINK_DIR-bin-hadoop27-scala_${SCALA_BIN_VERSION}.tgz"
    fetch_untar_file "$FLINK_FILE" "$APACHE_MIRROR/flink/flink-$FLINK_VERSION/$FLINK_FILE"

    #Fetch Spark
    SPARK_FILE="$SPARK_DIR.tgz"
    fetch_untar_file "$SPARK_FILE" "$APACHE_MIRROR/spark/spark-$SPARK_VERSION/$SPARK_FILE"



  elif [ "START_ZK" = "$OPERATION" ];
  then
    mkdir -p /tmp/dev-storm-zookeeper
    start_if_needed dev_zookeeper ZooKeeper 10 "$STORM_DIR/bin/storm" dev-zookeeper
  elif [ "STOP_ZK" = "$OPERATION" ];
  then
    stop_if_needed dev_zookeeper ZooKeeper
    rm -rf /tmp/dev-storm-zookeeper
  elif [ "START_REDIS" = "$OPERATION" ];
  then
    CMD="cd $PROJECT_DIR && ./stream-bench.sh START_LOCAL_REDIS"
    ssh -f "$REDIS_NODE" $CMD
    sleep 2
  elif [ "START_LOCAL_REDIS" = "$OPERATION" ];
  then
    cp "../conf/redis_conf/redis.conf" "$REDIS_DIR/redis_test.conf"
    echo "bind $REDIS_NODE" >> "$REDIS_DIR/redis_test.conf"
    start_if_needed redis-server Redis 1 "$REDIS_DIR/src/redis-server" "$REDIS_DIR/redis_test.conf"
    cd data
    $LEIN run -n --configPath ../conf/benchmarkConf.yaml
    cd ..
  elif [ "STOP_REDIS" = "$OPERATION" ];
  then
    CMD="cd $PROJECT_DIR && ./stream-bench.sh STOP_LOCAL_REDIS"
    ssh -f "$REDIS_NODE" $CMD
  elif [ "STOP_LOCAL_REDIS" = "$OPERATION" ];
  then
    stop_if_needed redis-server Redis
    rm -f dump.rdb
  elif [ "START_STORM" = "$OPERATION" ];
  then
    start_if_needed daemon.name=nimbus "Storm Nimbus" 3 "$STORM_DIR/bin/storm" nimbus
    start_if_needed daemon.name=supervisor "Storm Supervisor" 3 "$STORM_DIR/bin/storm" supervisor
    start_if_needed daemon.name=ui "Storm UI" 3 "$STORM_DIR/bin/storm" ui
    start_if_needed daemon.name=logviewer "Storm LogViewer" 3 "$STORM_DIR/bin/storm" logviewer
    sleep 20
  elif [ "STOP_STORM" = "$OPERATION" ];
  then
    stop_if_needed daemon.name=nimbus "Storm Nimbus"
    stop_if_needed daemon.name=supervisor "Storm Supervisor"
    stop_if_needed daemon.name=ui "Storm UI"
    stop_if_needed daemon.name=logviewer "Storm LogViewer"

  elif [ "START_KAFKA" = "$OPERATION" ];
  then
    for node_kafka in $KAFKA_NODES
    do
      CMD="cd $PROJECT_DIR && ./stream-bench.sh START_LOCAL_KAFKA"
      ssh -f "$node_kafka" $CMD
      sleep 10
    done
    create_kafka_topic
  elif [ "START_LOCAL_KAFKA" = "$OPERATION" ];
  then
    cp "../conf/kafka_conf/server.properties" "$KAFKA_DIR/config/server_$SELF_ID.properties"
    echo "broker.id=$SELF_ID" >> "$KAFKA_DIR/config/server_$SELF_ID.properties"
    echo "host.name=node$SELF_ID.ib.cluster" >> "$KAFKA_DIR/config/server_$SELF_ID.properties"
    echo "advertised.host.name=node$SELF_ID.ib.cluster" >> "$KAFKA_DIR/config/server_$SELF_ID.properties"
    echo "zookeeper.connect=$ZK_CONNECTIONS" >> "$KAFKA_DIR/config/server_$SELF_ID.properties"
    mkdir -p /tmp/kafka-logs/
    start_if_needed kafka\.Kafka Kafka 5 "$KAFKA_DIR/bin/kafka-server-start.sh" "$KAFKA_DIR/config/server_$SELF_ID.properties"
  elif [ "STOP_KAFKA" = "$OPERATION" ];
  then
    for node_kafka in $KAFKA_NODES
    do
      CMD="cd $PROJECT_DIR && ./stream-bench.sh STOP_LOCAL_KAFKA"
      ssh -f "$node_kafka" $CMD
    done
  elif [ "STOP_LOCAL_KAFKA" = "$OPERATION" ];
  then
    stop_if_needed kafka\.Kafka Kafka
    rm -rf /tmp/kafka-logs/
  elif [ "START_FLINK" = "$OPERATION" ];
  then
    start_if_needed org.apache.flink.runtime.jobmanager.JobManager Flink 1 $FLINK_DIR/bin/start-cluster.sh
  elif [ "STOP_FLINK" = "$OPERATION" ];
  then
    $FLINK_DIR/bin/stop-cluster.sh
  elif [ "START_SPARK" = "$OPERATION" ];
  then
    ssh -f $SPARK_MASTER $PROJECT_DIR$SPARK_DIR/sbin/start-all.sh
    sleep 10
#    start_if_needed org.apache.spark.deploy.master.Master SparkMaster 5 $SPARK_DIR/sbin/start-master.sh -h $SPARK_MASTER -p 7077
#    start_if_needed org.apache.spark.deploy.worker.Worker SparkSlave 5 $SPARK_DIR/sbin/start-slave.sh spark://$SPARK_MASTER:7077
  elif [ "STOP_SPARK" = "$OPERATION" ];
  then
    ssh -f $SPARK_MASTER $PROJECT_DIR$SPARK_DIR/sbin/stop-all.sh
    sleep 10
#    stop_if_needed org.apache.spark.deploy.master.Master SparkMaster
#    stop_if_needed org.apache.spark.deploy.worker.Worker SparkSlave
#    sleep 3
  elif [ "START_LOAD" = "$OPERATION" ];
  then
    cd data
    start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD --configPath ../$CONF_FILE
    cd ..
  elif [ "START_REDUCED_LOAD" = "$OPERATION" ];
  then
      CMD="cd $PROJECT_DIR && ./stream-bench.sh START_LOCAL_REDUCED_LOAD"
      ssh -f "$REDUCED_LOAD_HOST" $CMD
  elif [ "START_LOCAL_REDUCED_LOAD" = "$OPERATION" ];
  then
    cd data
    start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD_REDUCED --configPath ../$CONF_FILE
    cd ..
  elif [ "STOP_REDUCED_LOAD" = "$OPERATION" ];
  then
      CMD="cd $PROJECT_DIR && ./stream-bench.sh STOP_LOAD"
      ssh -f "$REDUCED_LOAD_HOST" $CMD
  # elif [ "STOP_LOCAL_REDUCED_LOAD" = "$OPERATION" ];
  # then
    # cd data
    # start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD_REDUCED --configPath ../$CONF_FILE
    # cd ..
  elif [ "STOP_LOAD" = "$OPERATION" ];
  then
    stop_if_needed leiningen.core.main "Load Generation"
    cd data
    $LEIN run -g --configPath ../$CONF_FILE || true
    cd ..
  elif [ "START_STORM_TOPOLOGY" = "$OPERATION" ];
  then
    "$STORM_DIR/bin/storm" jar ./storm-benchmarks/target/storm-benchmarks-0.1.0.jar storm.benchmark.AdvertisingTopology test-topo -conf $CONF_FILE
    sleep 15
  elif [ "STOP_STORM_TOPOLOGY" = "$OPERATION" ];
  then
    "$STORM_DIR/bin/storm" kill -w 0 test-topo || true
    sleep 10
  elif [ "START_SPARK_PROCESSING" = "$OPERATION" ];
  then
    "$SPARK_DIR/bin/spark-submit" --master "spark://$SPARK_MASTER:7077" --class spark.benchmark.KafkaRedisAdvertisingStream ./spark-benchmarks/target/spark-benchmarks-0.1.0.jar "$CONF_FILE" &
    sleep 5
  elif [ "STOP_SPARK_PROCESSING" = "$OPERATION" ];
  then
    stop_if_needed spark.benchmark.KafkaRedisAdvertisingStream "Spark Client Process"
  elif [ "START_FLINK_PROCESSING" = "$OPERATION" ];
  then
    "$FLINK_DIR/bin/flink" run ./flink-benchmarks/target/flink-benchmarks-0.1.0.jar --confPath $CONF_FILE &
    sleep 3
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
#  elif [ "START_APEX" = "$OPERATION" ];
#      then
#      "$APEX_DIR/engine/src/main/scripts/apex" -e "launch -local -conf ./conf/apex.xml ./apex-benchmarks/target/apex_benchmark-1.0-SNAPSHOT.apa -exactMatch Apex_Benchmark"
#             sleep 5
#  elif [ "STOP_APEX" = "$OPERATION" ];
#       then
#       pkill -f apex_benchmark
#  elif [ "START_APEX_ON_YARN" = "$OPERATION" ];
#       then
#        "$APEX_DIR/engine/src/main/scripts/apex" -e "launch ./apex-benchmarks/target/apex_benchmark-1.0-SNAPSHOT.apa -conf ./conf/apex.xml -exactMatch Apex_Benchmark"
#  elif [ "STOP_APEX_ON_YARN" = "$OPERATION" ];
#       then
#       APP_ID=`"$APEX_DIR/engine/src/main/scripts/apex" -e "list-apps" | grep id | awk '{ print $2 }'| cut -c -1 ; true`
#       if [ "APP_ID" == "" ];
#       then
#         echo "Could not find streaming job to kill"
#       else
#        "$APEX_DIR/engine/src/main/scripts/apex" -e "kill-app $APP_ID"
#         sleep 3
#       fi
  elif [ "RUN_FLINK_BENCHMARK" = "$OPERATION" ];
  then
    #    python3 -m venv myenv
    #    source myenv/bin/activate
    #    pip install pandas
    run "SETUP_FLINK"
    for ((i = 0 ; i < $NUM_RUNS ; i++)); do
      run "FLINK_TEST"
      cd data
      python dataformat.py -# $NUM_HOSTS -s flink -t $i
      cd ..
      wait
    done
  elif [ "RUN_FLINK_FB" = "$OPERATION" ];
  then
    #    python3 -m venv myenv
    #    source myenv/bin/activate
    #    pip install pandas
    run "SETUP_FLINK"
    for ((i = 0 ; i < $NUM_RUNS ; i++)); do
      run "FLINK_FLUCTUATION_TEST"
      cd data
      python dataformat.py -# $NUM_HOSTS -s flink2 -t $i
      cd ..
      wait
    done

  elif [ "RUN_SPARK_BENCHMARK" = "$OPERATION" ];
  then 
    #    python3 -m venv myenv
    #    source myenv/bin/activate
    #    pip install pandas
    echo "started runing spark benchmar"
    run "SETUP_SPARK"
    echo "Done seting up spark"
    for ((i = 0 ; i < $NUM_RUNS ; i++)); do
      run "SPARK_TEST"
      cd data 
      python dataformat.py -# $NUM_HOSTS -s spark -t $i 
      cd ..
    done
  elif [ "RUN_SPARK_FB" = "$OPERATION" ];
  then 
    #    python3 -m venv myenv
    #    source myenv/bin/activate
    #    pip install pandas
    echo "started runing spark benchmar"
    run "SETUP_SPARK"
    echo "Done seting up spark"
    for ((i = 0 ; i < $NUM_RUNS ; i++)); do
      run "SPARK_FLUCTUATION_TEST"
      cd data 
      python dataformat.py -# $NUM_HOSTS -s spark2 -t $i 
      cd ..
    done

  elif [ "STORM_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_STORM"
    run "START_STORM_TOPOLOGY"
    run "START_LOAD"
    sleep $TEST_TIME
    run "STOP_LOAD"
    run "STOP_STORM_TOPOLOGY"
    run "STOP_STORM"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "FLINK_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_FLINK"
    run "START_FLINK_PROCESSING"
    run "START_LOAD"
    sleep $TEST_TIME
    run "STOP_LOAD"
    run "STOP_FLINK_PROCESSING"
    run "STOP_FLINK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "FLINK_FLUCTUATION_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_FLINK"
    run "START_FLINK_PROCESSING"
    run "START_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_LOAD"
    run "START_REDUCED_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_REDUCED_LOAD"
    run "START_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_LOAD"
    run "STOP_FLINK_PROCESSING"
    run "STOP_FLINK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "SPARK_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_SPARK"
    run "START_SPARK_PROCESSING"
    run "START_LOAD"
    sleep $TEST_TIME
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "SPARK_FLUCTUATION_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_SPARK"
    run "START_SPARK_PROCESSING"
    run "START_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_LOAD"
    run "START_REDUCED_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_REDUCED_LOAD"
    run "START_LOAD"
    sleep $REDUCED_TEST_TIME
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "SPARK_SETUP" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    #run "START_SPARK"   
# elif [ "APEX_TEST" = "$OPERATION" ];
#  then
#    run "START_ZK"
#    run "START_REDIS"
#    run "START_KAFKA"
#    run "START_APEX"
#    run "START_LOAD"
#    sleep $TEST_TIME
#    run "STOP_LOAD"
#    run "STOP_APEX"
#    run "STOP_KAFKA"
#    run "STOP_REDIS"
#    run "STOP_ZK"
  elif [ "STOP_ALL" = "$OPERATION" ];
  then
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_FLINK_PROCESSING"
    run "STOP_FLINK"
#    run "STOP_STORM_TOPOLOGY"
#    run "STOP_STORM"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  elif [ "STOP_SPARK_BENCHMARK" = "$OPERATION" ];
  then
    run "STOP_LOAD"
    run "STOP_SPARK_PROCESSING"
    run "STOP_SPARK"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  else
    if [ "HELP" != "$OPERATION" ];
    then
      echo "UNKOWN OPERATION '$OPERATION'"
      echo
    fi
    echo "Supported Operations:"
    echo "SETUP: download and setup dependencies for running a single node test"
    echo "SETUP_FLINK: setup flink cluster for DAS5"
    echo "START_ZK: run a single node ZooKeeper instance on local host in the background"
    echo "STOP_ZK: kill the ZooKeeper instance"
    echo "START_REDIS: run a redis instance in the background"
    echo "STOP_REDIS: kill the redis instance"
    echo "START_KAFKA: run kafka cluster in the background"
    echo "STOP_KAFKA: kill kafka"
    echo "START_LOAD: run kafka load generation"
    echo "STOP_LOAD: kill kafka load generation"
    echo "START_STORM: run storm daemons in the background"
    echo "STOP_STORM: kill the storm daemons"
    echo "START_FLINK: run flink processes"
    echo "STOP_FLINK: kill flink processes"
    echo "START_SPARK: run spark processes"
    echo "STOP_SPARK: kill spark processes"
    echo "START_APEX: run the Apex test processing"
    echo "STOP_APEX: kill the Apex test processing"
    echo 
    echo "START_STORM_TOPOLOGY: run the storm test topology"
    echo "STOP_STORM_TOPOLOGY: kill the storm test topology"
    echo "START_FLINK_PROCESSING: run the flink test processing"
    echo "STOP_FLINK_PROCESSSING: kill the flink test processing"
    echo "START_SPARK_PROCESSING: run the spark test processing"
    echo "STOP_SPARK_PROCESSSING: kill the spark test processing"
    echo
    echo "STORM_TEST: run storm test (assumes SETUP is done)"
    echo "FLINK_TEST: run flink test (assumes SETUP is done)"
    echo "SPARK_TEST: run spark test (assumes SETUP is done)"
    echo
    echo "SPARK_SETUP: run and setup spark cluster"
    echo
    echo "APEX_TEST: run Apex test (assumes SETUP is done)"
    echo "STOP_ALL: stop everything"
    echo
    echo "RUN_FLINK_BENCHMARK: run flink benchmark in DAS5"
    echo "RUN_FLINK_FB: run flink benchmark in DAS5 for fluctuated workload experiment"
    echo "RUN_SPARK_BENCHMARK: run spark benchmark in DAS5"
    echo "RUN_SPARK_FB: run spark benchmark in DAS5 for fluctuated workload experiment"
    echo
    echo "STOP_SPARK_BENCHMARK: stop spark benchmark in DAS5"
    echo
    echo "HELP: print out this message"
    echo
    exit 1
  fi
}

if [ $# -lt 1 ];
then
  run "HELP"
else
  while [ $# -gt 0 ];
  do
    run "$1"
    shift
  done
fi

