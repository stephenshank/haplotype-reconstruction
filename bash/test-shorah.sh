######################################
#                                    #
#       ShoRAH Testing Script        #
#   For usage, see shorah-info.txt   #
#                                    #
######################################

workingDir=$(pwd)

if [ -d "shorah-tests/$1" ]; then
	printf "\nThe directory $workingDir/shorah-tests/$1 already exists. This will overwrite the data in that directory.\n"
	printf "Continue? [y/n]: "
	read response
	
	if [[ "$response" == "n" || "$response" == "N" ]]; then
		printf "\nExiting ShoRAH test script.\n\n"
		exit
	elif [[ "$response" == "y" || "$response" == "Y" ]]; then
		printf "\nClearing shorah-tests/$1..."
		eval "rm -r shorah-tests/$1"
	else
		printf "\nI didn't recognize that response. \
            \nExiting ShoRAH test script.\n\n"
		exit
	fi
fi

eval "mkdir shorah-tests/$1"

firstDataDir=$(ls -t test-data/454/$1/ | head -n 1)

fasta=$(ls -t test-data/454/$1/$firstDataDir/BP/1/*Reads.fna | xargs basename)

qual=$(ls -t test-data/454/$1/$firstDataDir/BP/1/*Reads.qual | xargs basename)

eval "cp test-data/454/$1/$firstDataDir/BP/1/$fasta \
         test-data/454/$1/$firstDataDir/BP/1/$qual shorah-tests/$1"

eval "cd shorah-tests/$1"

printf "\nFiltering reads...\n"

eval "qfilt -F $fasta $qual -q 15 -l 50 -P - -R 8 -j >> qfilt.fna 2>> qfilt.json"

printf "\nAssembling reads...\n"

eval "bealign -r $workingDir/env_C2V5.fas -e 0.5 -m HIV_BETWEEN_F -D discards.fna -R qfilt.fna aligned.bam"

printf "\nRunning ShoRAH. This may take a several minutes.\n"

eval "shorah.py --bam aligned.bam --fasta $workingDir/env_C2V5.fas"

testDir=$(pwd)

printf "\nResults have been stored at $testDir\n\n"
