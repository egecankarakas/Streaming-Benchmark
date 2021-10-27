#!/usr/bin/env bash
# Written by Stephan van der Putten s1528459

# Update frameworks configs
update_configs() {
  cp configurations/hadoop/etc/hadoop/* $HADOOP_HOME/etc/hadoop/
  cp configurations/spark/conf/* $SPARK_HOME/conf/ 
  cp configurations/hibench/conf/* $HIBENCH_HOME/conf/ 

  echo "Frameworks have their configs updated"
} 

# Check requirements SPARK_HOME and HADOOP_HOME and JAVA_HOME and HIBENCH_HOME
check_requirements() {
  if [ -z "$SPARK_HOME" ]; then
    echo 'No SPARK_HOME set'
    echo 'Set Spark env variable'
  fi

  if [ -z "$HADOOP_HOME" ]; then
    echo 'No HADOOP_HOME set'
    echo 'Set Hadoop env variable'
  fi

  if [ -z "$JAVA_HOME" ]; then
    echo 'No JAVA_HOME set'
    echo 'Set JAVA_HOME env variable'
  fi

  if [ -z "$HIBENCH_HOME" ]; then
    echo 'No HIBENCH_HOME set'
    echo 'Set HIBENCH_HOME env variable'
  fi

  if ! [[ -x "$(command -v mvn)" ]]; then
    echo 'No Maven set'
    echo 'Set Path to maven binary'
  fi
}

#  Setups hadoop and spark and Hibench
initial_setup() {
  # PATH to install directory 
  install_dir=/var/scratch/$USER

  echo "Starting setup"
  echo "Downloading Hadoop & Spark & HiBench & Maven "
  wget -nc https://apache.mirrors.nublue.co.uk/hadoop/common/hadoop-2.10.1/hadoop-2.10.1.tar.gz
  wget -nc https://mirror.novg.net/apache/spark/spark-2.4.7/spark-2.4.7-bin-hadoop2.7.tgz
  wget -nc https://apache.mirror.wearetriple.com/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz 
  git clone https://github.com/Intel-bigdata/HiBench.git $install_dir/hibench

  # create lib where hadoop and spark and maven will be stored
  mkdir -p $install_dir/hadoop $install_dir/spark $install_dir/maven 

  echo "Extracting files to install directory"
  # extract to correct folders
  tar zxf hadoop-2.10.1.tar.gz -C $install_dir/hadoop --strip-components=1
  tar zxf spark-2.4.7-bin-hadoop2.7.tgz -C $install_dir/spark --strip-components=1
  tar zxf apache-maven-3.6.3-bin.tar.gz -C $install_dir/maven --strip-components=1

  echo "Cleaning up"
  # rm tgz
  rm hadoop-2.10.1.tar.gz spark-2.4.7-bin-hadoop2.7.tgz apache-maven-3.6.3-bin.tar.gz

  ## Update environment variables
  ## assuming bashrc needs only these variables
  cp configurations/bashrc ~/.bashrc
  echo "export HADOOP_HOME=$install_dir/hadoop" >> ~/.bashrc
  echo "export SPARK_HOME=$install_dir/spark" >> ~/.bashrc
  # assuming the current java is java 8
  echo "export JAVA_HOME=$(sed 's/\(\/\jre\/bin\/java\)//g' <<<  "$(ls -la $(ls -la $(which java) | awk '{ print $NF}') | awk '{ print $NF }')")" >> ~/.bashrc
  echo "export HIBENCH_HOME=$install_dir/hibench" >> ~/.bashrc
  echo "export PATH=\$PATH:$install_dir/maven/bin" >> ~/.bashrc
  echo >> ~/.bashrc
  source ~/.bashrc
  check_requirements

  # give the current configs in all frameworks
  update_configs

  # link to install directory in scratch
  ln -s $install_dir ~/scratch

  source ~/.bashrc
  echo "Setup done"
}

# Downloads the dependencies used in the project and installs them
if [[ $1 == "--setup" ]]; then
  initial_setup
  exit 0
fi

# Finds nodes on das5 and setups Hadoop
initial_setup_hadoop() {
  # declare reserved nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # setups driver node
  ssh "${nodes[0]}" "mkdir -p /local/$USER/hadoop/"
  driver=$(ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}')
  sed -i "s/hdfs:\/\/.*:/hdfs:\/\/$driver:/g" $HADOOP_HOME/etc/hadoop/core-site.xml
  sed -i "22s/<value>.*:/<value>$driver:/g" $HADOOP_HOME/etc/hadoop/yarn-site.xml
  sed -i "26s/<value>.*</<value>$driver</g" $HADOOP_HOME/etc/hadoop/yarn-site.xml

  # setup worker nodes
  echo "" > $HADOOP_HOME/etc/hadoop/slaves
  for node in "${nodes[@]:1}"; do
    ssh "$node" 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}' >> $HADOOP_HOME/etc/hadoop/slaves
    #    echo $node >>$HADOOP_HOME/etc/hadoop/slaves

    # Clean up local and setups up local directory
    ssh "$node" "rm -rf /local/$USER/hadoop/*"
    ssh "$node" "mkdir -p /local/$USER/hadoop/data"
  done

  # Setup namenode
  ssh "$driver" 'yes | $HADOOP_HOME/bin/hadoop namenode -format'

  # Start daemons
  ssh "$driver" '$HADOOP_HOME/sbin/start-dfs.sh'
  ssh "$driver" '$HADOOP_HOME/sbin/start-yarn.sh'
  
}

# Finds nodes on das5 and setups HiBench
initial_setup_spark() {
  # declare reserved nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # setup driver node of spark (running next to yarn) in standalone and configs of spark in standalone
  echo "" > $SPARK_HOME/conf/spark-env.sh
  driver=$(ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}')
  echo "SPARK_MASTER_HOST=\"$driver\"" >>$SPARK_HOME/conf/spark-env.sh
  # ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}' >> $SPARK_HOME/conf/slaves
  echo "SPARK_MASTER_PORT=1336" >>$SPARK_HOME/conf/spark-env.sh
  echo "SPARK_LOCAL_DIRS=/local/$USER/spark/" >>$SPARK_HOME/conf/spark-env.sh
  echo "SPARK_MASTER_WEBUI_PORT=1335" >>$SPARK_HOME/conf/spark-env.sh
  #echo "SPARK_WORKER_INSTANCES="$(expr ${#nodes[@]} - 1)"" >> $SPARK_HOME/conf/spark-env.sh
  echo "SPARK_WORKER_MEMORY=15G" >>$SPARK_HOME/conf/spark-env.sh

  # Necessary for working with yarn
  echo "HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop" >>$SPARK_HOME/conf/spark-env.sh

  ssh "$driver" "rm -rf /local/$USER/spark/*"
  ssh "$driver" "mkdir -p /local/$USER/spark/"

  printf "\n"
  # setup worker nodes of spark
  echo >$SPARK_HOME/conf/slaves
  for node in "${nodes[@]:1}"; do
    # slower connection
    #$echo "$node" >> $SPARK_HOME/conf/slaves

    #highbang connection
    ssh "$node" 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}' >>$SPARK_HOME/conf/slaves
    ssh "$node" "rm -rf /local/$USER/spark/*"
    ssh "$node" "mkdir -p /local/$USER/spark/"
  done

  # start the remote driver
  ssh "$driver" '$SPARK_HOME/sbin/start-all.sh'
}

# Setup for HiBench
initial_setup_hibench() {
  # declare nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))

  # declare hdfs address to hibench
  sed -i "11s/hdfs:\/\/.*:/hdfs:\/\/$driver:/g" $HIBENCH_HOME/conf/hadoop.conf

  # build hibench benchmarks, currently only ml and micro
  #cd "$HIBENCH_HOME" && mvn -Phadoopbench -Psparkbench -Dmodules -Pmicro -Pml -Dspark=2.4 clean package

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
    initial_setup_hadoop
    initial_setup_spark
    initial_setup_hibench
  fi

  printf "\n"
  echo "We have reserved node(s): ${nodes[@]}"
  printf "The driver is node: ${nodes[0]}"
  printf "\n"

  echo "Cluster is setup for spark and hadoop!"

  exit 0
fi

# Runs the experiments and $2 is the amount of times
if [[ $1 == "--experiments-1" ]]; then
  # declare nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))
  driver=$(ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}')

  # make sure the setting is large for the benchmark
  sed -i "3s/small/large/g" $HIBENCH_HOME/conf/hibench.conf
  sed -i "3s/tiny/large/g" $HIBENCH_HOME/conf/hibench.conf
  sed -i "3s/micro/large/g" $HIBENCH_HOME/conf/hibench.conf
  sed -i "3s/large/large/g" $HIBENCH_HOME/conf/hibench.conf
  sed -i "3s/huge/large/g" $HIBENCH_HOME/conf/hibench.conf
  sed -i "3s/gigantic/large/g" $HIBENCH_HOME/conf/hibench.conf
  cd "$HIBENCH_HOME" && mvn -Phadoopbench -Psparkbench -Dmodules -Pml -Dspark=2.4 clean package
  cd -

  # setup configured dataset size from hibench.conf
  ssh $driver "$HIBENCH_HOME/bin/workloads/ml/kmeans/prepare/prepare.sh" 

  # clean report when starting tests
  # cp configurations/hibench.report > $HIBENCH_HOME/report/hibench.report

  start=1
  for i in $(eval echo "{$start..$2}")
  do
    printf "\n"
    echo "Running experiment: $i"

    ssh "$driver" "$HIBENCH_HOME/bin/workloads/ml/kmeans/spark/run.sh"
    ssh "$driver" "$HIBENCH_HOME/bin/workloads/ml/kmeans/hadoop/run.sh"
    wait
  done

  # show results
  echo "Results are shown for K-means:"
  cat $HIBENCH_HOME/report/hibench.report
  cp $HIBENCH_HOME/report/hibench.report experiments/
  wait
  exit 0
fi

# Runs the experiments and $2 is the amount of times
if [[ $1 == "--experiments-2" ]]; then
  # declare nodes
  declare -a nodes=($(preserve -llist | grep $USER | awk '{for (i=9; i<NF; i++) printf $i " "; if (NF >= 9+$2) printf $NF;}'))
  driver=$(ssh ${nodes[0]} 'ifconfig' | grep 'inet 10.149.*' | awk '{print $2}')

  # build hibench benchmarks again using different setting
  # small, large, huge
  if [[ -n $3 ]]
  then
     sed -i "3s/tiny/$3/g" $HIBENCH_HOME/conf/hibench.conf # really small
     sed -i "3s/small/$3/g" $HIBENCH_HOME/conf/hibench.conf
     sed -i "3s/large/$3/g" $HIBENCH_HOME/conf/hibench.conf
     sed -i "3s/huge/$3/g" $HIBENCH_HOME/conf/hibench.conf
     sed -i "3s/gigantic/$3/g" $HIBENCH_HOME/conf/hibench.conf # takes for too long
     sed -i "3s/bigdata/$3/g" $HIBENCH_HOME/conf/hibench.conf #takes far too long
     cd "$HIBENCH_HOME" && mvn -Phadoopbench -Psparkbench -Dmodules -Pmicro -Dspark=2.4 clean package
     cd -
  fi

  # setup configured dataset size from hibench.conf
  ssh $driver "$HIBENCH_HOME/bin/workloads/micro/wordcount/prepare/prepare.sh" 

  # clean report when starting tests
  # cp configurations/hibench.report > $HIBENCH_HOME/report/hibench.report

  start=1
  for i in $(eval echo "{$start..$2}")
  do
    printf "\n"
    echo "Running experiment: $i"

    #ssh "$driver" "$HIBENCH_HOME/bin/workloads/micro/wordcount/hadoop/run.sh "
    ssh "$driver" "$HIBENCH_HOME/bin/workloads/micro/wordcount/spark/run.sh"
    wait
  done

  # show results
  echo "Results for wordcount are shown:"
  cat $HIBENCH_HOME/report/hibench.report
  cp $HIBENCH_HOME/report/hibench.report experiments/
  wait
  exit 0
fi

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
  initial_setup_hadoop
  initial_setup_hibench
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
  ssh ${nodes[0]} '$HADOOP_HOME/sbin/stop-dfs.sh'
  ssh ${nodes[0]} '$HADOOP_HOME/sbin/stop-yarn.sh'
  ssh ${nodes[0]} '$SPARK_HOME/sbin/stop-all.sh'

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
  cp $HADOOP_HOME/etc/hadoop/* configurations/hadoop/etc/hadoop/
  cp $SPARK_HOME/conf/* configurations/spark/conf/
  cp $HIBENCH_HOME/conf/* configurations/hibench/conf/

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

# Help option
if [[ $1 == "--help" || $1 == "-h" ]]; then
  echo "Usage: $0 [option]"
  echo "--nodes n t                 Start cluster followed by (n) number of nodes to setup in das5 and (t) time allocation."
  echo "--setup                     Setup all initial software and packages."
  echo "--start-all                 Start cluster hadoop/spark default."
  echo "--get-configs               Pulls configs from frameworks spark hadoop and HiBench"
  echo "--update-configs            Sends configs from configuration to spark hadoop and HiBench"
  echo "---check-requirements       Check if the necessary Environment Variables are set"
  echo "--stop-all                  Stop cluster."
  echo "--experiments-1 n           Runs the k-means experiments n times."
  echo "--experiments-2 n size      Runs the wordcount experiments n times. Size is optional, e.g. tiny, small, bigdata, large, huge, gigantic"
  exit 0
fi

