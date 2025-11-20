#!/bin/bash

#-----------------------------------------------------------------------------------------
# Script information
script_name='HEAD CLEANER - MIRROR DEPRECATED'
script_version="1.1.0"
script_date='2025/11/20'

# Root directory
BASE_DIR="/share/HSAF_MIRROR"

# Age threshold (72 hours)
AGE="+72"
#-----------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------
# Info script start
echo " ==================================================================================="
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> START ..."

echo "Cleaning files older than 72 hours in: $BASE_DIR"

# Loop over level-1 subdirectories
for d in "$BASE_DIR"/*/; do
    [ -d "$d" ] || continue  # skip if not a directory

    echo "Processing folder: $d"

    # Find and delete files older than 72 hours by modification time
    find "$d" -maxdepth 1 -type f -mmin $((72*60)) -print -delete
done

echo "Cleanup completed."

# Info script end
echo " ==> "$script_name" (Version: "$script_version" Release_Date: "$script_date")"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="
# ----------------------------------------------------------------------------------------

