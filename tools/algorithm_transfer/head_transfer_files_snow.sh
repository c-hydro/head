#!/bin/bash -e

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD TRANSFER - SNOW - REALTIME'
script_version="1.0.7"
script_date='2024/06/10'
#-----------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------
# Define host
server_host='idrologia@130.251.104.19'
CONTROL_PATH=/tmp/rsync19_control_path_snow
# Days period
declare -a list_days=(5 5)
# Declare local folder(s) list
declare -a list_folders=(
	"/share/DEWETRA/nrt/h10/"
    "/share/DEWETRA/nrt/h12/"
    "/share/DEWETRA/nrt/h13/"
    "/share/DEWETRA/nrt/h34/"
)

# Declare filename(s) list
declare -a list_filename=(  
	"/share/DEWETRA/ancillary/sync_data/head_transfer_snow_h10.txt" 
    "/share/DEWETRA/ancillary/sync_data/head_transfer_snow_h12.txt" 
    "/share/DEWETRA/ancillary/sync_data/head_transfer_snow_h13.txt"
    "/share/DEWETRA/ancillary/sync_data/head_transfer_snow_h34.txt"
)
# Declare server folder
declare -a dst_base_dir=/share/archivio/experience/data/HSAF
#-----------------------------------------------------------------------------------------

LOCK_FILE=/tmp/sync19_lock_hsaf_precipitation2

if [ -e ${LOCK_FILE} ]; then
    echo file ${LOCK_FILE} exists, aborting
    exit 1
fi

# ----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."

#create a master ssh connection to avoid asking password for each rsync
ssh -o ControlPersist=yes -S ${CONTROL_PATH} -M ${server_host} true

# create a trap to close the master connection when the script ends
trap "rm ${LOCK_FILE}; ssh -S ${CONTROL_PATH} -O exit ${server_host}" EXIT

>${LOCK_FILE}

# ----------------------------------------------------------------------------------------
# 
#(
#flock -n 9 || exit 1

# Iterate over folder(s) 
for index in ${!list_folders[*]}; do 

    # ----------------------------------------------------------------------------------------
    # Info step starting
    echo " ===> Step: " $index " ... "
    echo " ===> Analyze folder: "${list_folders[$index]} 
    
    # Get filename(s)
    files_to_sync=$(find  ${list_folders[$index]} -mtime -${list_days[$index]}  -type f)

    echo "  ===> Files to synch : $(find  ${list_folders[$index]} -mtime -${list_days[$index]}  -type f | wc -l) "
    echo "  ===> files found with : find  ${list_folders[$index]} -mtime -${list_days[$index]}  -type f"

    # ----------------------------------------------------------------------------------------
    
    # ----------------------------------------------------------------------------------------
    # Iterate over filename(s)   
    for source_file in ${files_to_sync}; do
        
        # ----------------------------------------------------------------------------------------
        # Get information
        base_file=$(basename ${source_file})
        name_file="${base_file%.*}"
		
        old_IFS="$IFS"
        IFS='_'
        read -a file_name_tokens <<< "${base_file}"
        IFS="$old_IFS"
		      
        dst_dir=${dst_base_dir}/${file_name_tokens[1]}/${file_name_tokens[2]:0:4}/${file_name_tokens[2]:4:2}/${file_name_tokens[2]:6:2}/${file_name_tokens[2]:8:2}00
        dst_file_zip=${dst_dir}/${base_file}
        dst_file_unzip=${dst_dir}/${name_file}
        # ----------------------------------------------------------------------------------------
        
        # ----------------------------------------------------------------------------------------
        # Transfer file from local to server
        echo " ====> Send ${source_file} to ${dst_file_zip} ... "
        
        # Check unzipped file availability on server
        if ! ssh -S ${CONTROL_PATH} ${server_host} test -e $dst_file_unzip; then
            
            # debug command rsybc
            #echo rsync -e "ssh -S ${CONTROL_PATH}" -av -q --progress ${source_file} ${server_host}:${dst_file_zip} 
            #echo ssh -S ${CONTROL_PATH} ${server_host} mkdir -p ${dst_dir}
            
            # ----------------------------------------------------------------------------------------
            if ! ssh -S ${CONTROL_PATH} ${server_host} test -d ${dst_dir}; then
                ssh -S ${CONTROL_PATH} ${server_host} mkdir -p ${dst_dir}
            fi
            
            echo rsync -e "ssh -S ${CONTROL_PATH}" -av -q --progress ${source_file} ${server_host}:${dst_file_zip} 
            rsync -e "ssh -S ${CONTROL_PATH}" -av -q --progress ${source_file} ${server_host}:${dst_file_zip} || true
          
            if ! [ "$?" == "0" ]; then
                echo "ERROR in rsync. file: ${source_file}"
                #exit 3
            fi
            echo " ====> Send ${source_file} to ${dst_file_zip} ... DONE"
            # ----------------------------------------------------------------------------------------
        	
			file_ext_server="${dst_file_zip##*.}"
			file_name_server="${dst_file_zip%.*}"
			if [[ "$file_ext_server" == "gz" ]]; then

		        # ----------------------------------------------------------------------------------------
		        # Unzip file on server
		        echo " ====> Unzip ${dst_file_zip} ... "
		        
		        ssh -S ${CONTROL_PATH} ${server_host} "test -e $dst_file_zip"
		        if [ $? -eq 0 ]; then
		            
		            echo " =====> File exists on server"
		            ssh -S ${CONTROL_PATH} ${server_host} gzip -d ${dst_file_zip}
		            #ssh ${server_host} rm ${dst_file_zip}
		            echo " ====> Unzip ${dst_file_zip} ... DONE"

		        else
		            echo " =====> File does not exist on server"
		            echo " ====> Unzip ${dst_file_zip} ... FAILED"
		        fi
			fi
        
        else
            echo " ====> Send ${source_file} to ${dst_file_zip} ... SKIPPED. File previously sent."
        fi
        # ----------------------------------------------------------------------------------------
        
    done    
    # ----------------------------------------------------------------------------------------
    
    # ----------------------------------------------------------------------------------------
    # Info step ending
    echo " ===> Step: " $index " ... DONE"
    # ----------------------------------------------------------------------------------------

done
#) 9> ~/hsaf_op_chain/bin/utils/.lock_sync
# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------
