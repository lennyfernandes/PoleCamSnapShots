#!/bin/sh

ICTNO=$(cat < /home/qdnet/production/config/ictnumber)
ICT_LOG="/home/qdnet/production/logs/$ICTNO.log"

. /home/qdnet/production/scripts/commandToController.sh

echo "" >> $ICT_LOG
echo "-------------------------------------------------------------------" >> $ICT_LOG
echo "$(date) : movePendingSnapsToBacklogDir.sh" >> $ICT_LOG
echo "-------------------------------------------------------------------" >> $ICT_LOG

PENDING_HOURLY_SNAPSHOT_JPGS="/home/qdnet/production/hourlySnapShots/"

PENDING_SNAPSHOT_FILES_COUNT=`ls $PENDING_HOURLY_SNAPSHOT_JPGS | wc -l`

if [ $PENDING_SNAPSHOT_FILES_COUNT -gt 0 ]; then
    `mv /home/qdnet/production/hourlySnapShots/*.jpg /home/qdnet/production/hourlySnapShotsBacklog/`
    echo "$PENDING_SNAPSHOT_FILES_COUNT PREVIOUS HOUR(s) PENDING POST - MOVING TO BACKLOG DIRECTORY !!!" >> $ICT_LOG
else 
    echo "NO PREVIOUS HOUR PENDING POST !!!" >> $ICT_LOG
fi
echo "-------------------------------------------------------------------" >> $ICT_LOG

##################################################################
# FETCH THE VOLTAGE-CURRENT READING FOR THE PREVIOUS HOUR
##################################################################

func_command2Controller '$$SEND_DATA_ARRAY*' $VOLTAGE_CURRENT_READINGS

echo "-------------------------------------------------------------------" >> $ICT_LOG
