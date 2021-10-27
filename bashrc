# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
module load gcc
module load slurm 
module load python/3.6.0
module load java/jdk-1.8.0
module load python/3.5.2
export M2_HOME=/var/scratch/ddps2103/apache-maven-3.8.3
export PATH=${M2_HOME}/bin:${PATH}
module load prun
export PATH=/var/scratch/ddps2103/bin:${PATH}




