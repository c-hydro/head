#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD RUNNER - METOP-SM - REALTIME'
script_version="1.1.0"
script_date='2024/06/10'

script_folder='/home/hsaf/hyde-master/'

virtual_env_folder='/home/hsaf/library/hsaf_libs_python3/bin/'
virtual_env_name='hsaf_env_python3'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get file information
script_file='/home/hsaf/hyde-master/apps/hsaf/soil_moisture/HYDE_DynamicData_HSAF_ASCAT_OBS_NRT.py'
setting_file='/home/hsaf/hyde-master/apps/hsaf/soil_moisture/hyde_configuration_hsaf_ascat_obs_nrt_realtime.json'

# Get information (-u to get gmt time)
time_now=$(date +"%Y-%m-%d %H:00")
time_now="2024-06-11 12:00"
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
echo " ==> COMMAND LINE: " python $script_file -settings_file $setting_file -time $time_now

# Run python script (using setting and time)
python $script_file -settings_file $setting_file -time $time_now

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

