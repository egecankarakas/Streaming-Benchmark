import os
import sys
import getopt
import pandas as pd
import numpy as np

# options System, #Nodes,

countOfEvents = 'seen.txt'
latancyTime = 'updated.txt'




def createDataFile(numbNode = 1 , system = 'spark', testNumber = '1'):
    

    array_countOfEvent = np.loadtxt('seen.txt')
    array_latancyTime = np.loadtxt(latancyTime)
    array_NumbNode = np.full(array_countOfEvent.size, numbNode)
    array_testNumber = np.full(array_countOfEvent.size, testNumber)
    array_system = np.full(array_countOfEvent.size, system)



    df = pd.DataFrame(data=[array_countOfEvent, array_latancyTime, array_NumbNode, array_testNumber, array_system]).T
    #df.columns(['countOfEvent','latancyTime','#Nodes','testNubber','systems'])
    #print(df)

    df.to_csv(f"test_Nodes-{numbNode}_System-{system}_Test-{testNumber}.csv")

    return

def main(argv):
    numberOfNodes = ''
    system = ''
    testnumber = ''
    
    try:
        opts, args = getopt.getopt(argv, "h:#:s:t:",["help=","#Node=","System=","testNumber="])
    except getopt.GetoptError:
        print("help")
        sys.exit()

    for opt, arg in opts:
        if opt == '-h':
            print("required flags \n -# or #Node - number of nodes \n s or System - spark or flink \n t or testNumber - for test")
            sys.exit()
        elif opt in ("-#","--#Node"):
            numberOfNodes = arg
        elif opt in ("-s","--System"):
            system = arg
            #if args in ("sp","ar"):
            #    system = "spark"
            #elif arg is "flink":
            #    system = "flink"
            #else: 
            #    system = "flink"
            print(system)
        elif opt in ("-t","testNumber"):
            #an idicator of what test we are doing
            testnumber = arg
    return numberOfNodes, system, testnumber



if __name__ == "__main__":

    numberOfNodes, system, testnumber = main(sys.argv[1:]) 
    createDataFile(numberOfNodes, system, testnumber)


