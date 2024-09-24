#!/bin/bash -e

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT SOIL MOISTURE METOP (A+B+C) - REALTIME'
script_version="2.1.0"
script_date='2024/06/12'

# script mode
script_mode='realtime' # 'history' or 'realtime' 

# script arguments
days=7
proxy="" 

ftp_url="ftphsaf.meteoam.it"
ftp_usr="" 
ftp_pwd=""

#open -u sgabellani_r,gabellaniS334 ftphsaf.meteoam.it"

# Define products name
product_name=(
	"h122" 
	"h16" 
	"h103"
)

# Define product hourly maximum
product_hourly_max=(
	10
	20
	20
)

# check mode to choose ftp folder
if [ "$script_mode" == 'realtime' ]; then
	
	ftp_folder_raw=( 
		"/products/h122_test/h122_cur_mon_nc/"
		"/products/h16/h16_cur_mon_data/"
		"/products/h103/h103_cur_mon_data/"
	)
	 
elif [ "$script_mode" == 'history' ]; then 
    
	ftp_folder_raw=( 
		"/products/h122_test/h122_cur_mon_nc/"
		"/hsaf_archive/h16/%YYYY/%MM/%DD/%HH/"
		"/hsaf_archive/h103/%YYYY/%MM/%DD/%HH/"
	)
    
else 
    printf "This program requires 'history' or 'realtime' mode\n" 1>&2
    exit 1
fi 

# Define local folder(s)
local_folder_raw=(
	"/share/HSAF_SM/ascat/nrt/h122/%YYYY/%MM/%DD/%HH/"
	"/share/HSAF_SM/ascat/nrt/h16/%YYYY/%MM/%DD/%HH/"
	"/share/HSAF_SM/ascat/nrt/h103/%YYYY/%MM/%DD/%HH/"
)

# Define time format
product_time_format=(
	"C_LIIB_YYYYMMDDHH"
	"YYYYMMDD_HH" 
	"YYYYMMDD_HH"
)
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Get time
time_now=$(date '+%Y-%m-%d %H:00')
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Parser time now for checking
time_now_check=$(date -d "$time_now" +'%Y%m%d%H%M')

# Cycle(s) over product(s)
for ((i=0;i<${#ftp_folder_raw[@]};++i)); do

	# ----------------------------------------------------------------------------------------
	# Get product information
    ftp_folder_raw_product="${ftp_folder_raw[i]}" 
	local_folder_raw_product="${local_folder_raw[i]}" 
	product="${product_name[i]}" 
	data_hourly_max="${product_hourly_max[i]}"
	data_time_format="${product_time_format[i]}"

	# Info product start
	echo " ===> GET PRODUCT: "$product" ===> START "
	# ----------------------------------------------------------------------------------------
	
	# ----------------------------------------------------------------------------------------
	# Iterate over days
	for day in $(seq 0 $days); do
		
		# ----------------------------------------------------------------------------------------
		# Get time step
		time_step=$(date -d "$time_now ${day} days ago" +'%Y%m%d%H%M')

		year_step=${time_step:0:4}
		month_step=${time_step:4:2}
		day_step=${time_step:6:2}
		
		time_step_check=${year_step}${month_step}${day_step}"0000"
		
		if [ ${time_step_check:0:8} -ge ${time_now_check:0:8} ]; 
		then
    		hour_ref=${time_step:8:2}
		else
			hour_ref="23"
		fi  
		
		# Info day time start
		echo " ====> DAY TIMESTEP: "${time_step:0:8}" ===> START "
		# ----------------------------------------------------------------------------------------
		
		# ----------------------------------------------------------------------------------------
		# Iterate over hour
		for hour_step in $(seq -w $hour_ref -1 0); do
			
			# ----------------------------------------------------------------------------------------
			# Set hour reference
			if [ "$data_time_format" == 'YYYYMMDD_HH' ]; then
				ftp_time_step=${year_step}${month_step}${day_step}_${hour_step}	
			elif [ "$data_time_format" == 'C_LIIB_YYYYMMDDHH' ]; then 	
				ftp_time_step="C_LIIB_"${year_step}${month_step}${day_step}${hour_step}	
			else 
    			printf "This program requires 'YYYYMMDD_HH' or 'YYYYMMDDHH' time format\n" 1>&2
    			exit 1
			fi 

			# Info FTP time start
			echo " =====> FTP TIMESTEP: "$ftp_time_step" ===> START "
			# ----------------------------------------------------------------------------------------

			# ----------------------------------------------------------------------------------------
			# Define dynamic folder(s)
			ftp_folder_step_product=${ftp_folder_raw_product/'%YYYY'/$year_step}
			ftp_folder_step_product=${ftp_folder_step_product/'%MM'/$month_step}
			ftp_folder_step_product=${ftp_folder_step_product/'%DD'/$day_step}
			ftp_folder_step_product=${ftp_folder_step_product/'%HH'/$hour_step}

			local_folder_step_product=${local_folder_raw_product/'%YYYY'/$year_step}
			local_folder_step_product=${local_folder_step_product/'%MM'/$month_step}
			local_folder_step_product=${local_folder_step_product/'%DD'/$day_step}
			local_folder_step_product=${local_folder_step_product/'%HH'/$hour_step}
			# ----------------------------------------------------------------------------------------

			# ----------------------------------------------------------------------------------------	
			# Create folder(s)
			if [ ! -d "$local_folder_step_product" ]; then
				mkdir -p $local_folder_step_product
			fi
			# ----------------------------------------------------------------------------------------
			
			# ----------------------------------------------------------------------------------------
			# Check download activation
			cd $local_folder_step_product
			product_hourly_count=$(ls -1 | wc -l)

			if [ "$product_hourly_count" -eq "$data_hourly_max" ];then
				product_download_hourly=false
			else
				product_download_hourly=true
			fi
			# ----------------------------------------------------------------------------------------
			
			echo $ftp_folder_step_product $local_folder_step_product ${ftp_time_step}
			
			# ----------------------------------------------------------------------------------------
			# Condition for activating download
			if $product_download_hourly ; then 
				
				# ----------------------------------------------------------------------------------------
				# Info about download activation
				echo " ======> GET FILE(S) ... ACTIVATED. FILE(S) FOUND (N_FOUND = $product_hourly_count) ARE LESS THEN EXPECTED FILE(S) (N_EXP = $product_hourly_max) ! "

				# Get file list from ftp
				ftp_file_list=`lftp << ftprem
								open -u ${ftp_usr},${ftp_pwd} ${ftp_url}
								cd ${ftp_folder_step_product}
								cls -1 | sort -r | grep ${ftp_time_step} | sed -e "s/@//"
								close
								quit
ftprem`
				# ----------------------------------------------------------------------------------------
				
				# ----------------------------------------------------------------------------------------
				# Download file(s)	
				for ftp_file in ${ftp_file_list}; do
					
					echo -n " =======> DOWNLOAD FILE: ${ftp_file} IN ${local_folder_step_product} ..." 
					
					if ! [ -e ${local_folder_step_product}/${ftp_file} ]; then
						
						`lftp << ftprem
									open -u ${ftp_usr},${ftp_pwd} ${ftp_url}
									cd ${ftp_folder_step_product}
									get1 -o ${local_folder_step_product}/${ftp_file} ${ftp_file}
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

			else
				# ----------------------------------------------------------------------------------------
				# Info about download activation
				echo " ======> GET FILE(S) ... SKIPPED. ALL EXPECTED FILES (N_EXP = $product_hourly_count) WERE PREVIOUSLY DOWNLOADED! "
				# ----------------------------------------------------------------------------------------
			fi
			
			# Info FTP time end
			echo " =====> FTP TIMESTEP: "$ftp_time_step" ===> END "
			# ----------------------------------------------------------------------------------------

		done

		# Info time end
		echo " ====> DAY TIMESTEP: "${time_step:0:8}" ===> END "
		# ----------------------------------------------------------------------------------------

	done

	# Info product end
	echo " ===> GET PRODUCT: "$product" ===> END "
	# ----------------------------------------------------------------------------------------

done

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------









