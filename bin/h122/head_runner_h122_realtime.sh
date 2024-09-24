#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD RUNNER - METOP[B+C] SSM - REALTIME '
script_version="1.1.0"
script_date='2024/06/10'

script_folder='/share/home/idrologia/package/package_head/' 

virtual_env_folder='/share/home/idrologia/library/conda_head/bin/'
virtual_env_name='head_runner_libraries'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get file information
script_file='/home/idrologia/package/package_head/apps/soil_moisture/h122/app_sm_h122_main.py'
settings_file='/home/idrologia/project/hsaf/algorithm_runner/h122/head_runner_h122_realtime.json'

# Get information (-u to get gmt time)
time_now=$(date +"%Y-%m-%d %H:00")
#time_now="2024-06-11 12:00"
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Add path to pythonpath
export PYTHONPATH="${PYTHONPATH}:$script_folder"
# Add virtual env
export PATH=$virtual_env_folder:$PATH
source activate $virtual_env_name
#-----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."
echo " ==> COMMAND LINE: " python $script_file -settings_file $settings_file -time $time_now

# Run python script (using setting and time)
python $script_file -settings_file $settings_file -time "$time_now"

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

