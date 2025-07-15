#!/bin/bash

#-----------------------------------------------------------------------------------------
# Script information
SCRIPT_NAME='HEAD NOTIFY - PRECIPITATION - REALTIME'
SCRIPT_VERSION="1.0.0"
SCRIPT_DATE='2025/03/07'
#-----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
## PARAMETERS

# File template pattern (e.g., '*.txt' for all text files)
FILE_TEMPLATE="hsaf_h60_*.nc"

# Date template for extracting year, day, month, and time from the file name
DATE_TEMPLATE="hsaf_h60_([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{4})_fdisk.nc"

# File creation minimum time (in minutes)
FILE_CREATION_MINS=120

# Directory to monitor
WATCH_DIR="/share/DEWETRA/nrt/precipitation/h60/"
#WATCH_DIR="/share/TMP/"

# remote server details
#REMOTE_USER="jupyter"
#REMOTE_HOST="130.251.104.142"
#REMOTE_DIR="/home/jupyter/data/TEST/"
REMOTE_USER="idrologia"
REMOTE_HOST="172.16.104.19"
REMOTE_DIR="/share/archivio/experience/data/HSAF/h60/"
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
## FUNCTIONS
# Function to check if file is completely copied
is_file_copied_D() {
    local file="$1"
    local size1=$(stat -c%s "$file")
    sleep 1
    local size2=$(stat -c%s "$file")
    if [ "$size1" -eq "$size2" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if file is fully copied
is_fully_copied() {
    local file="$1"
    local size1
    local size2

    # Try to get the file size, handle errors gracefully
    size1=$(stat -c%s "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot stat file $file. Retrying..."
        return 1  # File is still being copied or an error occurred
    fi

    sleep 1

    size2=$(stat -c%s "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot stat file $file. Retrying..."
        return 1  # File is still being copied or an error occurred
    fi

    if [ "$size1" -eq "$size2" ]; then
        return 0  # File is fully copied
    else
        echo "File $file is still being copied. Retrying..."
        return 1  # File is still being copied
    fi
}

# Function to check if file is fully copied
is_file_fully_copied() {
    local file="$1"
    local size1
    local size2

    # Try to get the file size, handle errors gracefully
    size1=$(stat -c%s "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot stat file $file"
        return 1  # File is still being copied or an error occurred
    fi

    sleep 1

    size2=$(stat -c%s "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot stat file $file"
        return 1  # File is still being copied or an error occurred
    fi

    if [ "$size1" -eq "$size2" ]; then
        return 0  # File is fully copied
    else
        return 1  # File is still being copied
    fi
}
# Function to perform rsync
perform_rsync() {
    local file="$1"
    local remote_user="$2"
    local remote_host="$3"
    local remote_dir="$4"
    local rsync_command="rsync -avz \"$file\" \"$remote_user@$remote_host:$remote_dir\""
    echo " :::::: RSYNC EXECUTION ... "
    echo " ::::::: CMD: $rsync_command"
    eval $rsync_command
    echo " ::::::: FILE $file HAS BEEN COPIED TO $remote_host:$remote_dir"
    echo " :::::: RSYNC EXECUTION ... DONE"
}
# ----------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------
## CHECKS
# Sanity check for WATCH_DIR
if [ ! -d "$WATCH_DIR" ]; then
    echo " ERROR: WATCH_DIR ($WATCH_DIR) does not exist."
    exit 1
fi
# ----------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------
## EXECUTION START
echo " ==================================================================================="
echo " ==> "$SCRIPT_NAME" (Version: "$SCRIPT_VERSION" Release_Date: "$SCRIPT_DATE")"
echo " ==> START ..."

# Kill any existing inotifywait processes monitoring the same directory
pkill -f "inotifywait -m -e close_write --format %w%f $WATCH_DIR"

# info main START
echo " ===> NOTIFY FILES ... "

# Monitor directory for new files matching the template
echo "inotifywait -m -r -e close_write --format '%w%f' "$WATCH_DIR" | while read NEW_FILE"
inotifywait -m -r -e close_write --format '%w%f' "$WATCH_DIR" | while read NEW_FILE
do	

	# info found file START
	echo " ====> FOUND FILE $NEW_FILE ... $WATCH_DIR/$FILE_TEMPLATE"
	
    # Remove trailing slash from WATCH_DIR if present
    WATCH_DIR="${WATCH_DIR%/}"
    
	# Get the temporary name
	TMP_NAME=$(basename "$NEW_FILE")
	# Get the directory name
	NEW_DIR=$(dirname "$NEW_FILE")
    
    # info check filename string START
    echo " =====> CHECK FILENAME STRING $NEW_FILE ...  " 
    if [[ "$TMP_NAME" == .* ]]; then
		
		# info clean START
		echo " ======> CLEAN FILENAME STRING $NEW_FILE ...  " 
	
   		# Remove part before the first dot
		NO_PREFIX_NAME=$(echo "$TMP_NAME" | cut -d'.' -f2-)
		# Remove part after the last dot
		NO_SUFFIX_NAME=$(echo "$NO_PREFIX_NAME" | rev | cut -d'.' -f2- | rev)
  		# Construct the new file name
  		NEW_FILE="$NEW_DIR/$NO_SUFFIX_NAME"
  		
    	# info clean END
  		echo " ======> CLEAN FILENAME STRING $NEW_FILE ... APPLIED"
  		
  		# info check filename string END
  		echo " =====> CHECK FILENAME STRING $NEW_FILE ... DONE" 
  		
	else
		# info check filename string END
  		echo " =====> CHECK FILENAME STRING $NEW_FILE ... NOT NEEDED" 
	fi
    
    # Check if the file is completely copied
    if is_fully_copied "$NEW_FILE"; then
    
    	# Get the directory name
    	NEW_DIR=$(dirname "$NEW_FILE")
    	# Get the file name
    	NEW_NAME=$(basename "$NEW_FILE")
		
		# Check if the new file matches the template
		if [[ "$NEW_NAME" == $FILE_TEMPLATE ]]; then
			
			# info extrac date START
			echo " =====> EXTRACT DATE FROM $NEW_FILE ... "	
			
		    # Extract year, month, day, and time from the file name using the date template
		    FILE_NAME=$(basename "$NEW_FILE")
		    if [[ "$FILE_NAME" =~ $DATE_TEMPLATE ]]; then
		        YEAR=${BASH_REMATCH[1]}
		        MONTH=${BASH_REMATCH[2]}
		        DAY=${BASH_REMATCH[3]}
		        TIME=${BASH_REMATCH[4]}
		        echo " ======> EXTRACTED DATE: YEAR=$YEAR, MONTH=$MONTH, DAY=$DAY, TIME=$TIME "
		    else
		        echo " ======> EXTRACTED DATE: SKIPPED. File name does not match the expected pattern."
		        continue
		    fi
		    
		    # info extract date END
		    echo " =====> EXTRACT DATE FROM $NEW_FILE ... DONE "
		    
			# info transfer file START
			echo " =====> TRANFER FILE $NEW_FILE ... "	
		    
		    # check the creation time
		    if find . -type f -name "$NEW_FILE" -cmin -$FILE_CREATION_MINS | grep -q "$NEW_FILE"; then
  				
  				# info creation parameters
  				echo " ======> FILE $NEW_FILE ... WAS CREATED WITHIN THE LAST $FILE_CREATION_MINS MINUTES"
  				
		    	# Check if the remote directory exists and create it if it doesn't
		    	# echo ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/$YEAR/$MONTH/$DAY"
		        ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/$YEAR/$MONTH/$DAY"
		       	
		        # Check if the file already exists on the remote server
		        if ssh "$REMOTE_USER@$REMOTE_HOST" "[ ! -f $REMOTE_DIR/$YEAR/$MONTH/$DAY/$FILE_NAME ]"; then
		            # Perform rsync using the function
		            perform_rsync "$NEW_FILE" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_DIR/$YEAR/$MONTH/$DAY"
		            
		        	# info transfer file END (done)
					echo " =====> TRANFER FILE $NEW_FILE ... DONE"
		        else
		        	# info transfer file END (done)
					echo " =====> TRANFER FILE $NEW_FILE ... SKIPPED. File already exists on the remote server"
		        fi	
			
			else
				# info creation parameters
  				echo " ======> FILE $NEW_FILE ... WAS NOT CREATED WITHIN THE LAST $FILE_CREATION_MINS MINUTES"
  				# info transfer file END (done)
				echo " =====> TRANFER FILE $NEW_FILE ... SKIPPED. File is older than the selected period"
			fi

			# info found file END (done)
			echo " ====> FOUND FILE $NEW_FILE ... DONE "
		
		else
			# info found file END (skipping)
			echo " ====> FOUND FILE $NEW_FILE ... SKIPPED. File does not match the template "
		fi
		
    else
		# info found file END (skipping)
		echo " ====> FOUND FILE $NEW_FILE ... SKIPPED. File is still being copied"
    fi
    
done

# info main END
echo " ===> NOTIFY FILES ... DONE "

# EXECUTION END
echo " ==> "$SCRIPT_NAME" (Version: "$SCRIPT_VERSION" Release_Date: "$SCRIPT_DATE")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

