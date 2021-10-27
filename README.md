# Streaming-Benchmark
Reproducing "Benchmarking Distributed Stream Data Processing Systems" paper



# DataFormaing 
The streaming-benchmark library returns data in 2 different files 1 being the seen.txt and the other hte update.txt file. This is the python script to create 1 csv with this data. So we can run muliptle test and not have to edit the test script. Possible Flags
-# number of nodes used in test 
-s the system used for us spark or flink 
-t test number - self ID. 
returns - file with format of "test_Nodes-{}_System-{}_Test-{}.csv"

