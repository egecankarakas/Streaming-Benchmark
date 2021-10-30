# Streaming-Benchmark
Reproducing "Benchmarking Distributed Stream Data Processing Systems" paper


# SPARK TEST
In order to run spark test. 
reserve nodes 
you have to be in scratch directory 

go the master node
co the file


## Resever nodes
1) With the number of spark nodes you would like to test being n. 
2) Reverse a total about of nodes equal to n*2+1. This will provide enough enodes for a RedisNode, Seperate Kafka nodes and your spark nodes. 
3) edit stream-bench.sh file manually set REDIS_NODE IP, KAFKA NODE ID ,SPARK_MASTER IP, SPARK_SLAVES
6) You are now able to run ./stream-bench.sh RUN_SPARK_BENCHMARK

# DataFormaing 
The streaming-benchmark library returns data in 2 different files 1 being the seen.txt and the other hte update.txt file. This is the python script to create 1 csv with this data. So we can run muliptle test and not have to edit the test script. Possible Flags
-# number of nodes used in test 
-s the system used for us spark or flink 
-t test number - self ID. 
returns - file with format of "test_Nodes-{}_System-{}_Test-{}.csv"

