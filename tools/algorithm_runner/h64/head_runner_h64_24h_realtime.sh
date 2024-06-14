#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD RUNNER - PRECIPITATION H64 - ACCUMULATED 24 HOUR - REALTIME'
script_version="1.2.0"
script_date='2024/06/10'

script_folder='/share/home/idrologia/package/package_head/' 

virtual_env_folder='/share/home/idrologia/library/conda_head/bin/'
virtual_env_name='head_runner_libraries'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get file information
script_file='/home/idrologia/package/package_head/apps/precipitation/h64/app_precipitation_h64_main.py'
settings_file='/home/idrologia/project/hsaf/algorithm_runner/h64/head_runner_h64_24h_realtime.json'

# Get information (-u to get gmt time)
time_now=$(date +"%Y-%m-%d %H:00")
# time_now='2018-07-23 00:00' # DEBUG 
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
echo " ==> COMMAND LINE: " python $script_file -settingfile $setting_file -time $time_now

# Run python script (using setting and time)
python $script_file -settings_file $settings_file -time "$time_now"

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

