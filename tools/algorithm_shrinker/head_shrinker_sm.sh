#!/bin/bash -e

# ----------------------------------------------------------------------------------------
# script generic information
script_name='HEAD - SHRINKER - SOIL MOISTURE PRODUCT - NRT HISTORY'
script_version="1.0.0"
script_date='2024/02/01'

# scritp data condition(s)
dst_reset=false		# if true, reset dst file

# script executable
exec_nccopy='/share/home/idrologia/library/netcdf-c/bin/nccopy' 
shrink_arg='-d9 -s'

# script data arg(s)
data_days_list=(
	367 
	367
)

data_description_list=(
	"SOIL MOISTURE MAP 00:00 - ASCAT AND ECMWF - NC" 
	"SOIL MOISTURE MAP 12:00 - ASCAT AND ECMWF - NC"
)

data_period_list=(
	"2019-01-01 :: NOW"
	"2019-01-01 :: NOW"
)

data_name_list=(
	"sm 00:00"
	"sm 12:00"
)

data_expected_list=(
	1
	1
)

data_active_list=(
	true
	true
)

data_file_src_list=(
	"hsaf_ascat-obs_%YYYY%MM%DD0000_italy.nc"
	"hsaf_ascat-obs_%YYYY%MM%DD1200_italy.nc"
)


data_file_dst_list=(
	"hsaf_ascat-obs_%YYYY%MM%DD0000_italy.nc"
	"hsaf_ascat-obs_%YYYY%MM%DD1200_italy.nc"
)

# case realtime
data_folder_src_list=(
	"/share/SM_OBS_MOD/map_sm/%YYYY/%MM/%DD/"
	"/share/SM_OBS_MOD/map_sm/%YYYY/%MM/%DD/"
)
	
data_folder_dst_list=(
	"/share/SM_OBS_MOD/map_sm_compressed/%YYYY/%MM/%DD/"
	"/share/SM_OBS_MOD/map_sm_compressed/%YYYY/%MM/%DD/"
)

# Script time arg(s) (actual time)
time_now=$(date '+%Y-%m-%d %H:00')
time_now='2023-01-01'
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# info script start
echo " ==================================================================================="
echo " ==> "${script_name}" (Version: "${script_version}" Release_Date: "${script_date}")"
echo " ==> START ..."

# parse and check time information
time_data_now=$(date -d "${time_now}" +'%Y%m%d%H%M')
echo " ===> INFO TIME -- TIME: ${time_data_now}"

# iterate over data name(s)
for ((i=0;i<${#data_description_list[@]};++i)); do

	# ----------------------------------------------------------------------------------------
	# get data information
	data_folder_src_raw="${data_folder_src_list[i]}"
	data_file_src_raw="${data_file_src_list[i]}"
	data_folder_dst_raw="${data_folder_dst_list[i]}"
	data_file_dst_raw="${data_file_dst_list[i]}"
	data_name_step="${data_name_list[i]}"
	data_description_step="${data_description_list[i]}"
	data_period_step="${data_period_list[i]}"
	data_days_step="${data_days_list[i]}"
	data_active_step="${data_active_list[i]}"

	# info description and name start
	echo " ====> PRODUCT NAME '"${data_name_step}"' ... "
	echo " ::: PRODUCT DESCRIPTION: ${data_description_step}"
	# ----------------------------------------------------------------------------------------

	# ----------------------------------------------------------------------------------------
	# parse data period to extract data start and data end
	data_period_nospace=$(echo $data_period_step | tr -d '[:space:]')

	# extract data start and data end
	IFS_DEFAULT="$IFS"
	IFS="::"; read data_period_start data_period_end <<< "$data_period_nospace"
	IFS="$IFS_DEFAULT"
	unset IFS_DEFAULT
	# adjust data format
	data_period_start=${data_period_start/':'/''}
	data_period_end=${data_period_end/':'/''}

	# time period now
	time_period_now=$(date -d "${time_now}" +'%Y%m%d')
	# time period start
	time_period_start=$(date -d "${data_period_start}" +'%Y%m%d')
	# time period end
	if [ "${data_period_end}" == "NOW" ] ; then
		time_period_end=$(date -d "${time_now}" +'%Y%m%d')
	else
		time_period_end=$(date -d "${data_period_end}" +'%Y%m%d')
	fi

	# info time(s)
	echo " ::: PRODUCT PERIOD: ${data_period_step}"
	echo " ::: PRODUCT NOW: ${time_period_now} -- PRODUCT START: ${time_period_start} PRODUCT END: ${time_period_end}"
	# ----------------------------------------------------------------------------------------

	# ----------------------------------------------------------------------------------------
	# check the time with the reference product period
	if [[ $time_period_now -ge $time_period_start ]] && [[ $time_period_now -le $time_period_end ]] ; then

		# ----------------------------------------------------------------------------------------
		# flag to activate datasets
		if [ "${data_active_step}" = true ] ; then

			# ----------------------------------------------------------------------------------------
			# iterate over days
			for day in $(seq ${data_days_step} -1 0); do

				# ----------------------------------------------------------------------------------------
				# get time step
				time_data_step=$(date -d "$time_now ${day} days ago" +'%Y%m%d%H%M')
				year_data_step=${time_data_step:0:4};
				month_data_step=${time_data_step:4:2}; day_data_step=${time_data_step:6:2}
				hour_data_step='00'

				# info time step start
				echo " =====> TIME: "${time_data_step:0:8}" ... "
				# ----------------------------------------------------------------------------------------

				# ----------------------------------------------------------------------------------------
				# Define dynamic folder(s)
				data_folder_src_step=${data_folder_src_raw/'%YYYY'/$year_data_step}
				data_folder_src_step=${data_folder_src_step/'%MM'/$month_data_step}
				data_folder_src_step=${data_folder_src_step/'%DD'/$day_data_step}
				data_folder_src_step=${data_folder_src_step/'%HH'/$hour_data_step}

				data_file_src_step=${data_file_src_raw/'%YYYY'/$year_data_step}
				data_file_src_step=${data_file_src_step/'%MM'/$month_data_step}
				data_file_src_step=${data_file_src_step/'%DD'/$day_data_step}
				data_file_src_step=${data_file_src_step/'%HH'/$hour_data_step}
				
				data_folder_dst_step=${data_folder_dst_raw/'%YYYY'/$year_data_step}
				data_folder_dst_step=${data_folder_dst_step/'%MM'/$month_data_step}
				data_folder_dst_step=${data_folder_dst_step/'%DD'/$day_data_step}
				data_folder_dst_step=${data_folder_dst_step/'%HH'/$hour_data_step}

				data_file_dst_step=${data_file_dst_raw/'%YYYY'/$year_data_step}
				data_file_dst_step=${data_file_dst_step/'%MM'/$month_data_step}
				data_file_dst_step=${data_file_dst_step/'%DD'/$day_data_step}
				data_file_dst_step=${data_file_dst_step/'%HH'/$hour_data_step}
				
				# Create data path(s)
				data_path_src_step=${data_folder_src_step}/${data_file_src_step}
				data_path_dst_step=${data_folder_dst_step}/${data_file_dst_step}
				# ----------------------------------------------------------------------------------------

				# ----------------------------------------------------------------------------------------
				# Create folder(s)
				if [ ! -d "$data_folder_dst_step" ]; then
					mkdir -p $data_folder_dst_step
				fi
				# ----------------------------------------------------------------------------------------

				# ----------------------------------------------------------------------------------------
				# remove file (if flag_reset = true)
				if [ "${dst_reset}" = true ] ; then
					if [ -e ${data_path_dst_step} ]; then
						rm -rf ${data_path_dst_step}
					fi
				fi

				# check file exist or not in the destination folder
				if [ -e ${data_path_dst_step} ]; then
					shrink_dst=false
				else
					shrink_dst=true
				fi
				
				# Compose fx
				exec_fx_shrink="${exec_nccopy} ${shrink_arg} ${data_path_src_step} ${data_folder_dst_step}/${data_file_dst_step}"
				# ----------------------------------------------------------------------------------------

				# ----------------------------------------------------------------------------------------
				# flag to activate download
				if [ "${shrink_dst}" = true ] ; then
					
					# info shrink file
					echo -n " ======> SHRINK FILE: ${exec_nccopy} ${shrink_arg} ${data_path_src_step} ${data_path_dst_step}"
					
					# shrink command
					cd ${exec_folder}
					if ${exec_nccopy} ${shrink_arg} ${data_path_src_step} ${data_path_dst_step} > /dev/null 2>&1; then
						sleep 1
				 		echo " ... DONE!"
					else
						echo " ... FAILED! SHRINK ERROR!"
					fi
					
					# info time step end
					echo " =====> TIME: "${time_data_step:0:8}" ... DONE "

				else

					# info time step end
					echo " =====> TIME: "${time_data_step:0:8}" ... SKIPPED. FILE SHRUNK PREVIOUSLY."
				fi
				# ----------------------------------------------------------------------------------------

			done

			# info name end
			echo " ====> PRODUCT NAME '"${data_name_step}"' ... DONE"
			# ----------------------------------------------------------------------------------------

		else

			# ----------------------------------------------------------------------------------------
			# info name end
			echo " ====> PRODUCT NAME '"${data_name_step}"' ... SKIPPED. SHRINK IS NOT ACTIVATED."
			# ----------------------------------------------------------------------------------------

		fi
		# ----------------------------------------------------------------------------------------

	else

		# ----------------------------------------------------------------------------------------
		# info name end
		echo " ====> PRODUCT NAME '"${data_name_step}"' ... SKIPPED. TIME NOW NOT IN THE TIME PERIOD"
		# ----------------------------------------------------------------------------------------

	fi
	# ----------------------------------------------------------------------------------------

done

# info script end
echo " ==> "${script_name}" (Version: "${script_version}" Release_Date: "${script_date}")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------
