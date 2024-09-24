#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD RUNNER - PRECIPITATION H60/H60B - HISTORY'
script_version="1.3.0"
script_date='2024/08/10'

script_folder='/share/home/idrologia/package/package_head/' 

virtual_env_folder='/share/home/idrologia/library/conda_head/bin/'
virtual_env_name='head_runner_libraries'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get file information
script_file='/home/idrologia/package/package_head/apps/precipitation/h60/app_precipitation_h60_main.py'
settings_file='/home/idrologia/project/hsaf/algorithm_runner/h60/head_runner_h60_history.json'

# Get information (-u to get gmt time)
time_now=$(date +"%Y-%m-%d %H:00")
time_now='2024-02-13 00:00' # DEBUG 

# Get time days execution
time_period_days=1000
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

# Iterate over days
time_run=$(date -d "$time_now" +'%Y-%m-%d %H:00')
for time_period_step in $(seq 0 $time_period_days); do

    # Parse time information
    time_step=$(date -d "$time_run ${time_period_step} days ago" +'%Y-%m-%d %H:00')

	# Define python script (using settings and time)
	echo -n " ===> COMMAND LINE: python $script_file -settings_file $settings_file -time "$time_step" "

	# Run python script (using setting and time)
	python $script_file -settings_file $settings_file -time "$time_step"
    status=$?
    echo " ... DONE!"

done

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

