# Streaming-Benchmark
Reproducing "Benchmarking Distributed Stream Data Processing Systems" paper with Yahoo Streaming Benchmark.

# SETUP
Project is designed to work in /var/scratch/$USER/ path in DAS-5 cluster. Make sure you are using Python3.6 or higher and Java1.8 set.
YSB project also requires MVN_HOME to be set, and LEIN to be installed and set. For those you can check .bashrc profile.

We start with getting YSB Project. Simply get Yahoo Streaming benchmark
```bash 
wget https://github.com/yahoo/streaming-benchmarks/archive/refs/heads/master.zip
cp stream-bench.sh streaming-benchmarks-master/
cd streaming-benchmarks-master
./stream-bench.sh SETUP
```
If you get error in the SETUP phase, you can use the update pom.xml files which is worked to resolve dependency issues.

From here on, we will be using updated script to run the benchmarks.
# EXPERIMENT SETUP
Benchmark script is designed to work with no arguments. Therefore, before running any experiment, make sure to set following variables
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



## Procedure nodes
1) With the number of spark nodes you would like to test being n. 
2) Reverse a total about of nodes equal to n*2+1. This will provide enough enodes for a RedisNode, Seperate Kafka nodes and your spark nodes.
3) setup python envorment with source venv/bin/activate 
3) edit stream-bench.sh file manually set REDIS_NODE IP, KAFKA NODE ID ,SPARK_MASTER IP, SPARK_SLAVES, and if need be change project directory
6) You are now able to run ./stream-bench.sh RUN_SPARK_BENCHMARK

# DataFormaing 
The streaming-benchmark library returns data in 2 different files 1 being the seen.txt and the other hte update.txt file. This is the python script to create 1 csv with this data. So we can run muliptle test and not have to edit the test script. Possible Flags
-# number of nodes used in test 
-s the system used for us spark or flink 
-t test number - self ID. 
returns - file with format of "test_Nodes-{}_System-{}_Test-{}.csv"

