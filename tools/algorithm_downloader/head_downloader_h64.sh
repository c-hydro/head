#!/bin/bash -e

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT PRECIPITATION H64 - REALTIME'
script_version="2.5.0"
script_date='2024/06/07'

# script mode
script_mode='realtime' # 'history' or 'realtime' 
# script period
days=10
# Script argument(s)
local_folder_raw="/share/HSAF_PRECIPITATION/nrt/h64/%YYYY/%MM/%DD/"

# script ftp settings
proxy=""

ftp_machine="ftphsaf.meteoam.it"
ftp_url="ftphsaf.meteoam.it"
ftp_usr="" 
ftp_pwd=""

# check mode to choose ftp folder
if [ "$script_mode" == 'realtime' ]; then
	ftp_folder_raw="/products/h64/h64_cur_mon_data/" # realtime
elif [ "$script_mode" == 'history' ]; then 
    ftp_folder_raw="/hsaf_archive/h64/%YYYY/%MM/%DD/" # history
else 
    printf "This program requires 'history' or 'realtime' mode\n" 1>&2
    exit 1
fi 
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Get time
time_now=$(date '+%Y-%m-%d')
#time_now='2024-02-13'
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."

# get credentials from .netrc (if not defined in the bash script)
if [[ -z ${ftp_usr} || -z ${ftp_pwd} ]]; then

	# check .netrc file availability
	netrc_file=~/.netrc
	if [ ! -f "${netrc_file}" ]; then
	  echo "${netrc_file} does not exist. Please create it to store login and password on your machine"
	  exit 0
	fi

	# get information from .netrc file
	ftp_usr=$(awk '/'${ftp_machine}'/{getline; print $4}' ~/.netrc)
	ftp_pwd=$(awk '/'${ftp_machine}'/{getline; print $6}' ~/.netrc)

fi
echo " ===> INFO MACHINE -- URL: ${ftp_url} -- USER: ${ftp_usr}"

# Iterate over day(s)
for day in $(seq 0 $days); do
    
    # ----------------------------------------------------------------------------------------
    # Get time step
	date_step=$(date -d "${time_now} -${day} days" +%Y%m%d)
	# ----------------------------------------------------------------------------------------
	
    # ----------------------------------------------------------------------------------------
    # Info time start
    echo " ===> TIME_STEP: "$date_step" ===> START "
	
    # Define time step information
    date_get=$(date -u -d "$date_step" +"%Y%m%d%H")
    doy_get=$(date -u -d "$date_step" +"%j")

    year_get=$(date -u -d "$date_step" +"%Y")
    month_get=$(date -u -d "$date_step" +"%m")
    day_get=$(date -u -d "$date_step" +"%d")
    hour_get=$(date -u -d "$date_step" +"%H")
    # ----------------------------------------------------------------------------------------
	
	# ----------------------------------------------------------------------------------------
	# Iterate over hour(s)
	if [ "$script_mode" == 'realtime' ]; then
		count_start=${hour_get}
		count_end=${hour_get}
	elif [ "$script_mode" == 'history' ]; then 
		count_start=23
		count_end=0
	fi 
	
	# set unique cycle to hours
	count_start=0
	count_end=0
	for hour in $(seq ${count_start} -1 ${count_end}); do
		
		# ----------------------------------------------------------------------------------------
		# get hour 
		if [ "$script_mode" == 'realtime' ]; then
			hour_get=$(printf $(date '+%H'))
		elif [ "$script_mode" == 'history' ]; then 
			hour_get=$(printf "%02d" ${hour})
		fi
		# ----------------------------------------------------------------------------------------
		
    	# ----------------------------------------------------------------------------------------
    	# Info time start
    	echo " ===> HOUR_STEP: "$hour_get" ===> START "

		# Define ftp folder(s)
		ftp_folder_def=${ftp_folder_raw/'%YYYY'/$year_get}
		ftp_folder_def=${ftp_folder_def/'%MM'/$month_get}
		ftp_folder_def=${ftp_folder_def/'%DD'/$day_get}
		ftp_folder_def=${ftp_folder_def/'%HH'/$hour_get}

		# Define dynamic folder(s)
    	local_folder_def=${local_folder_raw/'%YYYY'/$year_get}
    	local_folder_def=${local_folder_def/'%MM'/$month_get}
    	local_folder_def=${local_folder_def/'%DD'/$day_get}    
    	if [ "$script_mode" == 'realtime' ]; then	
			local_folder_def=${local_folder_def/'%HH'/'realtime'}
		elif [ "$script_mode" == 'history' ]; then 
			local_folder_def=${local_folder_def/'%HH'/$hour_get}
		fi
		# ----------------------------------------------------------------------------------------

		# ----------------------------------------------------------------------------------------	
		# Create folder(s)
		if [ ! -d "$local_folder_def" ]; then
			mkdir -p $local_folder_def
		fi
		# ----------------------------------------------------------------------------------------
		
		# ----------------------------------------------------------------------------------------
		# Get file list from ftp
		# Example
		# open -u "sgabellani_r","gabellaniS334" "ftphsaf.meteoam.it"
		# cd "/products/h60/h60_cur_mon_data/"
		# cls -1 | sort -r | grep "20230515" | sed -e "s/@//"
		
		ftp_file_list=`lftp << EOF
		set ftp:proxy ${proxy}
		open -u ${ftp_usr},${ftp_pwd} ${ftp_url}
		cd ${ftp_folder_def}
		cls -1 | sort -r | grep ${date_step} | sed -e "s/@//"
		close
		quit
EOF`
	   	#echo " ===> LIST FILES: $ftp_file_list "
	   	#exit
		# ----------------------------------------------------------------------------------------

		# ----------------------------------------------------------------------------------------
		# Download file(s)	
		for ftp_file in ${ftp_file_list}; do
		    
		    echo -n " ====> DOWNLOAD FILE: ${ftp_file} IN ${local_folder_def} ..." 
		    
			if ! [ -e ${data_folder_dynamic_src_def}/${ftp_file} ]; then
				
				`lftp << ftprem
					        set ftp:proxy  ${proxy}
							open -u ${ftp_usr},${ftp_pwd} ${ftp_url}
							cd ${ftp_folder_def}
							get1 -o ${local_folder_def}/${ftp_file} ${ftp_file}
							close
							quit
ftprem`

				if [ $? -eq 0 ] > /dev/null 2>&1; then
			 		echo " DONE!"
				else
					echo " FAILED [FTP ERROR]!"
				fi
			
			else
				echo " SKIPPED! File previously downloaded!"
			fi
		    # ----------------------------------------------------------------------------------------
		    
		done
		# ----------------------------------------------------------------------------------------
		

		# ----------------------------------------------------------------------------------------
    	# Info hour end
    	echo " ===> HOUR_STEP: "$hour_get" ===> END "
    	# ----------------------------------------------------------------------------------------
    	
	done
	
	# ----------------------------------------------------------------------------------------
	# Info time end
	echo " ===> TIME_STEP: "$date_step" ===> END "
    # ----------------------------------------------------------------------------------------
	
done

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

