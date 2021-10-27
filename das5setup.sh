#!/usr/bin/env bash

#copied form stream-bench.sh
#need to place this in bashrc

SPARK_VERSION=${SPARK_VERSION:-"2.3.1"}
SPARK_DIR="spark-$SPARK_VERSION-bin-hadoop2.7"


#  Setups hadoop and spark and Hibench
initial_setup() {
  # PATH to install directory 
  install_dir=/var/scratch/$USER

  echo "Starting setup"
  echo "Will Call stream-bench SETUP "

  git clone https://github.com/yahoo/streaming-benchmarks.git

  echo "have download yahoo streaming-benchmarks from github"

  wait
  ## Update environment variables
  ## assuming bashrc needs only these variables
  cp bashrc ~/.bashrc
  echo >> ~/.bashrc
  source ~/.bashrc
  echo "have copied correct formated bashrc to ~/.bashrc"

  #cp stream-bench.sh streaming-benchmarks/stream-bench_.sh

  # need to copy of pom.xml file
  cp pom.xml streaming-benchmarks/
  echo "copied pom.xml file"

  pwd
  echo "will run setup from stream-bench"
  cd streaming-benchmarks
  pwd
  bash ./stream-bench.sh SETUP 



  #need to copy spark configs to spark 
  cp spark/conf/* streaming-benchmarks/$SPARK_DIR/conf/
  echo "spark conf have been copied"

  cp stream-bench.sh streaming-benchmarks/stream-bench_edited.sh
  echo "Setup done" 
}

# Downloads the dependencies used in the project and installs them
if [[ $1 == "--setup" ]]; then
  initial_setup
  exit 0
fi

# Finds nodes on das5 and setups HiBench
initial_setup_spark() {
  truncate -s 0 streaming-benchmarks/$SPARK_DIR/conf/slaves
  truncate -s 0 streaming-benchmarks/$SPARK_DIR/conf/spark-env.sh

  # declare reserved nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # setup driver node of spark (running next to yarn) in standalone and configs of spark in standalone
  echo "" > $SPARK_DIR/conf/spark-env.sh
  driver=$(ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}')
  echo "SPARK_MASTER_HOST=\"$driver\"" >>streaming-benchmarks/$SPARK_DIR/conf/spark-env.sh

  #ssh "$driver" "rm -rf /local/$USER/spark/*"
  #ssh "$driver" "mkdir -p /local/$USER/spark/"

  printf "\n"
  # setup worker nodes of spark
  echo >streaming-benchmarks/$SPARK_DIR/conf/slaves
  for node in "${nodes[@]:1}"; do
    # slower connection
    #$echo "$node" >> $SPARK_HOME/conf/slaves

    #highbang connection
    ssh "$node" 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}' >>streaming-benchmarks/$SPARK_DIR/conf/slaves
    #ssh "$node" "rm -rf /local/$USER/spark/*"
    #ssh "$node" "mkdir -p /local/$USER/spark/"
  done
}

moves_files() {
  echo "moving files"
  cp stream-bench.sh streaming-benchmarks/stream-bench_edited.sh
  echo "moves stream-bench_edited"
  echo "need to move python files"
  cp dataformat.py streaming-benchmarks/data/
  echo "moved dataformats"

}


# Setups the amount of nodes and takes flag amount of minutes
if [[ $1 == "--nodes" ]]; then
  echo "Setting up a node cluster of size $2"
  declare -a nodes=()

  # actual preserving, normally 15 minutes, can be more
  preserve -# $2 -t 00:$3:00
  sleep 2
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # if nodes got reserved we can run otherwise we have to wait
  if [ ${nodes[0]} = "-" ]; then
    echo "Nodes are waiting to be reserved, try --start-all when ready"
  else
    echo "We have reserved node(s): ${nodes[@]}"

    # setup hadoop/spark/HiBench
    initial_setup_spark
  fi

  printf "\n"
  echo "We have reserved node(s): ${nodes[@]}"
  printf "The driver is node: ${nodes[0]}"
  printf "\n"

  echo "Cluster is setup for spark"

  exit 0
fi

if [[$1 == "--experiments-1"]]; then 
  echo "Using $2 nodes for N of $3"
  cd streaming-benchmarks
  for i in {0. .$3}
  do 
    bash ./stream-bench.sh SPARK_TEST 
    python 




# Checks the requirements of environments variable, not if they are correct necessarily
if [[ $1 == "--check-requirements" ]]; then
  check_requirements
  echo "Requiments checked!"
  echo "If not message than everything is set."

  start_all
  exit 0
fi

# Starts all and builds Hibench
start_all() {
  initial_setup_spark
}

# Start up SPARK and HADOOP daemons/processes with Hibench
if [[ $1 == "--start-all" ]]; then
  echo "Starting all"
  start_all
  wait
  exit 0
fi

# Stops all drivers and workers
stop_all() {
  # declare node
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # send message to drivers to stop
  ssh ${node[0]} 'streaming-benchmarks/$SPARK_DIR/sbin/stop-all.sh'

  # deallocates reservation
  scancel "$(preserve -llist | grep $USER | awk '{print $1}')"
}

# Stops all drivers and workers
if [[ $1 == "--stop-all" ]]; then
  echo "Stopping all"
  stop_all
  wait
  exit 0
fi

# Get the configurations 
get_configs() {
  # copy current settings to configurations
  cp $SPARK_HOME/conf/* configurations/spark/conf/

  echo "Configuration updated in /configurations"
}

#  Get the configurations
if [[ $1 == "--get-configs" ]]; then
  get_configs
  wait
  exit 0
fi

# Update frameworks configs
if [[ $1 == "--update-configs" ]]; then
  update_configs
  wait
  exit 0
fi

if [[ $1 == "--movefiles"]]; then 
  moves_files
  wait
  exit 0
fi

# Help option
if [[ $1 == "--help" || $1 == "-h" || $1 == "" ]]; then
  echo "Usage: $0 [option]"
  echo "--nodes n t                 Start cluster followed by (n) number of nodes to setup in das5 and (t) time allocation."
  echo "--setup                     Setup all initial software and packages. make sure stream-bench is correctly installed"
  echo "--movefiles                 Moves needed files to location"
  echo "--setup-spark               Setup all nodes sets master ip as node[0] and all other nodes are in slaves file"
  #echo "--start-all                 Start cluster hadoop/spark default."
  #echo "---check-requirements       Check if the necessary Environment Variables are set"
  echo "--stop-all                  Stop cluster."
  echo "--experiments-1 node n           Runs the k-means experiments n times."
  #echo "--experiments-2 n size      Runs the wordcount experiments n times. Size is optional, e.g. tiny, small, bigdata, large, huge, gigantic"
  exit 0
fi

