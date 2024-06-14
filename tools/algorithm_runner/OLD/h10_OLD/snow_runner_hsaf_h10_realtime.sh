#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='SNOW RUNNER - HSAF H10'
script_version="1.1.0"
script_date='2024/01/31'

script_folder='/share/home/idrologia/package/package_hsaf/' 

virtual_env_folder='/share/home/idrologia/library/conda_hsaf/bin/'
virtual_env_name='hsaf_runner_libraries'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get file information
script_file='/share/home/idrologia/package/package_hsaf/h10/hsaf_product_h10_main.py'
settings_file='/share/home/idrologia/project/hsaf/algorithm_runner/h10/snow_runner_hsaf_h10_realtime.json'

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
echo " ==> COMMAND LINE: " python3 $script_file -settingfile $setting_file -time $time_now

# Run python script (using setting and time)
python3 $script_file -settings_file $settings_file -time "$time_now"

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

