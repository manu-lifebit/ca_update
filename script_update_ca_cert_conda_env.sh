#!/bin/bash

#===============================================================================
# Script for modifying the ca-certificates of the conda environments. 
# Author: Manuel Castro
# Date: 2021/12/30
# Description: This script allows to substitute the default ca-certificates of all  
# the conda environments present in our system by a custom ca-certificate. To do 
# that I implemented three different software modules: the first one allows to  
# replace the ca-certs of all the available conda envs (module1). The second one 
# is designed to be executed in the system profile as daemon. So any new conda env 
# created will be detected and the ca-cert file will be replaced (module2). The 
# third module implements a more generic function that allows to execute custom 
# scripts when we activate or deactivate a conda environment (module3). 
#
# NOTE: In order to execute the monitor module at every system startup create a .sh
# script in the folder /etc/profile.d with the content: 
# nohup bash script_update_ca_cert_conda_env.sh -m -c /tmp/cloudos_user_envs -o /home/jovyan/out_inotify.log &
#
# Usage: The script usage varies according to the task to be done.
# Check the help section for more information and examples.
#     
#===============================================================================

#===============================================================================
# Define variables                                         
#===============================================================================

CONDA_ENV_REPLACE_SSL=FALSE
CONDA_ENV_MONITOR=FALSE
CONDA_ACTIVATE_SCRIPTS=FALSE
TIME=60
TARGET_CA_CERT=/etc/ssl/certs/ca-certificates.crt
BASE_CA_CERT=cacert.pem
ALT_CONDA_ENV_PATH=/tmp/cloudos_user_envs
OUTFILE=out_inotify.log
ACTIVATION_SCRIPT=""
DEACTIVATION_SCRIPT=""
ENV_NAME=""

#===============================================================================
# Help                                                     
#===============================================================================
help()
{
   # Display help
   echo " This script updates the ca-certificates in conda environments."
   echo
   echo " The script contains 3 different modules: "
   echo
   echo " 1-Replace CA-cert: Replaces the ca-cert files in all the available conda envs."
   echo " e.g. bash script_update_ca_cert_conda_env.sh -r -c /tmp/cloudos_user_envs"
   echo
   echo " 2-Monitor: Monitor the creation of new conda env and replaces the ca-cert file."
   echo " e.g. nohup bash script_update_ca_cert_conda_env.sh -m -c /tmp/cloudos_user_envs -o out_inotify.log &"
   echo
   echo " 3-Activate scripts: Adds custom activation/deactivation script to the specified conda env"
   echo " e.g. bash script_update_ca_cert_conda_env.sh -s -e envtest -a custom_a_script.sh -d custom_d_script.sh"
   echo
   echo " options:"
   echo " -h     Print this help."
   echo " -r     Activates the Replace SSL module."
   echo " -m     Activates the Monitor module."
   echo " -s     Activates the Activate scripts module."
   echo " -t     Time in seconds to wait for new ca-cert files after a new conda env creation. (module 2)"
   echo " -T     Name of the ca-cert file used to replace. Default /etc/ssl/certs/ca-certificates.crt (module 1,2)"
   echo " -b     Name of the ca-cert file to replace. Default cacert.pem (module 1,2)"
   echo " -c     System path where conda envs are installed. Default /tmp/cloudos_user_envs. (module 1,2)"
   echo " -o     Output file name used to store the log messages from the monitor module. Default out_inotify.log. (module 2)"
   echo " -e     Name of the conda environment from which we want to add the activation scripts . Default NULL (module 3)"
   echo " -a     Name of the script we want to add to the activation folder of a specific conda environment. Default NULL (module 3)"
   echo " -d     Name of the script we want to add to the deactivation folder of a specific conda environment. Default NULL (module 3)"
   echo
}

if (($# == 0)); then
       help
       exit
fi

#================================================================================
# Main program                                             
#================================================================================


# Get the options
while getopts "hrmst:T:b:c:o:e:a:d:" option; do
   case $option in
      h) # display Help
         help
         exit;;
      r) # Module replace ssl 
         CONDA_ENV_REPLACE_SSL=TRUE;;
      m) # Module monitor ssl env 
         CONDA_ENV_MONITOR=TRUE;;
      s) # Module add env activation scripts 
         CONDA_ACTIVATE_SCRIPTS=TRUE;;
      t) # Wait time
         TIME=$OPTARG;;
      T) # Target CA-cert
         TARGET_CA_CERT=$OPTARG;;
      b) # Base CA-cert
         BASE_CA_CERT=$OPTARG;;
      c) # ALT conda env path
         ALT_CONDA_ENV_PATH=$OPTARG;;
      o) # Output log file
         OUTFILE=$OPTARG;;
      e) # env name to copy activation scripts
         ENV_NAME=$OPTARG;;
      a) # Activation script path
         ACTIVATION_SCRIPT=$OPTARG;;
      d) # Deactivation script path
         DEACTIVATION_SCRIPT=$OPTARG;;          
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
      *) 
         help
         exit;;
   esac
done

#===============================================================================
# MODULE 1: REPLACE CA-CERT 
#===============================================================================

if [ "$CONDA_ENV_REPLACE_SSL" = TRUE ];then
   echo "Replacing the $BASE_CA_CERT files in all the available conda environments ..."
   #Substitute the ca-cert file in the base conda env
   sudo cp $CONDA_PREFIX/ssl/$BASE_CA_CERT $CONDA_PREFIX/ssl/backup_$BASE_CA_CERT
   sudo cp $TARGET_CA_CERT $CONDA_PREFIX/ssl/$BASE_CA_CERT
   echo "$BASE_CA_CERT file replaced in the conda base env"

   #Substitute the ca-cert file in all the available secondary conda env
   for env in `ls $ALT_CONDA_ENV_PATH/`;do
	  if [[ -f "$ALT_CONDA_ENV_PATH/$env/ssl/$BASE_CA_CERT" ]]; then
      sudo cp $ALT_CONDA_ENV_PATH/$env/ssl/$BASE_CA_CERT $ALT_CONDA_ENV_PATH/$env/ssl/backup_$BASE_CA_CERT
		sudo cp $TARGET_CA_CERT $ALT_CONDA_ENV_PATH/$env/ssl/$BASE_CA_CERT
      echo "$BASE_CA_CERT file replaced in the conda $env env"
	  fi
   done
   echo "$BASE_CA_CERT files were replaced in all the available conda environments"
fi

#===============================================================================
# MODULE 2: MONITOR MODE 
#===============================================================================

if [ "$CONDA_ENV_MONITOR" = TRUE ];then
   #Check if inotify tool is installed.
   status=`inotifywait -h > /dev/null |echo $?`
   if [ $status -ne 0 ];then
      echo "Please install inotify-tools to use this parameter" >&2
      exit 1
   fi

   #Run monitor mode to detect the creation of new conda envs
   echo "Running the monitor mode to replace ca-certficates in all the new conda env created."
   touch $OUTFILE
   echo "Check the output log in $OUTFILE"
   inotifywait -q -m $ALT_CONDA_ENV_PATH -e create |
	  while read path action dir; do
	        if [[ -f "$path$dir/ssl/$BASE_CA_CERT" ]]; then	
		         echo "Change detected date $(date) in ${path} action ${action} in dir ${dir}. Replacing the $BASE_CA_CERT file" >> $OUTFILE
               sudo cp $TARGET_CA_CERT $path$dir/ssl/$BASE_CA_CERT
               echo "$BASE_CA_CERT file replaced in $dir env" >> $OUTFILE
	        else
		         echo "Change detected date $(date) in ${path} action ${action} in dir ${dir}. Waiting for ssl folder creation ..." >> $OUTFILE
		          sleep 60
               if [[ -f "$path$dir/ssl/$BASE_CA_CERT" ]]; then
                  echo "Change detected date $(date) in ${path} action ${action} in dir ${dir}. $BASE_CA_CERT file DETECTED! Replacing file ..." >> $OUTFILE
                  sudo cp $TARGET_CA_CERT $path$dir/ssl/$BASE_CA_CERT
                  echo "$BASE_CA_CERT file replaced in $dir env" >> $OUTFILE
               else
                  echo "Change detected date $(date) in ${path} action ${action} in dir ${dir}. $BASE_CA_CERT file NOT DETECTED in $dir env after $TIME seconds. Please increase the wait time if your new env is not empty ..." >> $OUTFILE   
               fi
            fi
      done
fi

#===============================================================================
# MODULE 3: ACTIVATE SCRIPTS 
#===============================================================================

if [ "$CONDA_ACTIVATE_SCRIPTS" = TRUE ];then
   echo "Adding custom activation scripts to the $ENV_NAME conda env ..."
    #Determine path of the target env
    ENV_PATH=`conda info -e | grep $ENV_NAME |sed 's/*//g'|sed 's/ \+/,/g'|cut -d "," -f2`
    if [[ ! -z "$ACTIVATION_SCRIPT" ]];then
       sudo cp $ACTIVATION_SCRIPT $ENV_PATH/etc/conda/activate.d/
    fi
    if [[ ! -z "$DEACTIVATION_SCRIPT" ]];then
       sudo cp $DEACTIVATION_SCRIPT $ENV_PATH/etc/conda/deactivate.d/
    fi
    echo "All the custom activation scripts were added. Please re-activate the env $ENV_NAME to apply changes"
 fi

echo "WORK FINISHED"
exit
   

