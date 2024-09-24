#!/bin/bash

#-----------------------------------------------------------------------------------------
# Script information
script_name="HEAD CLEANER - DEPRECATED DATASETS BY MINUTES - HISTORY"
script_version="1.2.0"
script_date="2024/08/10"
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Get script information
script_file="head_cleaner_deprecated_datasets_mins.sh"

# Get time information (-u to get gmt time)
time_script_now=$(date -u +"%Y-%m-%d %H:00")
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Folder of remote and local machine(s)
group_datasets_name=(
	"DATA ANCILLARY - HSAF PRECIPITATION - H60/H60B"
	"DATA ANCILLARY - HSAF PRECIPITATION - H61/H61B"
)

group_folder_datasets=(
	"/share/DEWETRA/ancillary/h60/"
	"/share/DEWETRA/ancillary/h61/"
)

group_file_datasets_clean=(
	true
	true
)

group_file_datasets_elapsed_days=(
	30
	30
)
#-----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."
echo " ===> EXECUTION ..."

time_script_now=$(date -d "$time_script_now" +'%Y-%m-%d 00:00')
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Iterate over tags
for datasets_id in "${!group_datasets_name[@]}"; do

	# ----------------------------------------------------------------------------------------
	# Get values of tag(s) and folder(s)        
	datasets_name=${group_datasets_name[datasets_id]}
	
	folder_datasets=${group_folder_datasets[datasets_id]}

	file_datasets_clean=${group_file_datasets_clean[datasets_id]} 
	file_datasets_elapsed_days=${group_file_datasets_elapsed_days[datasets_id]}
	
	# Info datasets type start
	echo " ====> DATASETS TYPE ${datasets_name} ... "
	# ----------------------------------------------------------------------------------------
	
	# ----------------------------------------------------------------------------------------
	# Check sync activation
	if ${file_datasets_clean} ; then
		
		# ----------------------------------------------------------------------------------------
		# Iterate over filename
		for file_datasets_name in $(find ${folder_datasets} -type f -mmin +${file_datasets_elapsed_days}); do
			echo " ====> DELETE FILENAME ${file_datasets_name} ... "
			
			if [ -f "$file_datasets_name" ] ; then
    			rm "$file_datasets_name"
    			echo " ====> DELETE FILENAME ${file_datasets_name} ... DONE"
			else
				echo " ====> DELETE FILENAME ${file_datasets_name} ... FAILED. FILE NOT FOUND"
			fi
			
		done
		# ----------------------------------------------------------------------------------------
		
		# ----------------------------------------------------------------------------------------
		# Find empty folders
		for folder_empty_name in $(find ${folder_datasets} -type d -empty); do
			
			echo " ====> DELETE EMPTY FOLDER ${folder_empty_name} ... "
			if [ -d "$folder_empty_name" ] ; then
				rmdir ${folder_empty_name} -vp --ignore-fail-on-non-empty {} 
				echo " ====> DELETE EMPTY FOLDER ${file_datasets_name} ... DONE"
			else
				echo " ====> DELETE EMPTY FOLDER ${file_datasets_name} ... FAILED. FOLDER NOT FOUND"
			fi
			
		done
		# ----------------------------------------------------------------------------------------
		
		# ----------------------------------------------------------------------------------------
		# Info datasets type end
		echo " ====> DATASETS TYPE ${datasets_name} ... DONE"
		# ----------------------------------------------------------------------------------------
		
	else
	
		# ----------------------------------------------------------------------------------------
		# Info tag end (not activated)
		echo " ====> DATASETS TYPE ${datasets_name} ... SKIPPED. SYNC NOT ACTIVATED"
		# ----------------------------------------------------------------------------------------
		
	fi
	# ----------------------------------------------------------------------------------------
	
done

# Info script end
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

