#!/bin/sh

. /home/qdnet/production/scripts/commonFuncs.sh
. /home/qdnet/production/scripts/commandToController.sh

echo "" >> $ICT_LOG
echo "-------------------------------------------------------------------" >> $ICT_LOG
echo "$(date) : onBootUpdateServer.sh" >> $ICT_LOG
echo "-------------------------------------------------------------------" >> $ICT_LOG

func_IsTimeSyncd
if [ $? -eq 0 ]; then func_command2Controller '$$IMAGE_FAILURE*' $SERIAL_PORT_DATA_DUMP && func_SystemHalt && exit 1; fi

func_buildImgNamePattern

func_check_camera_online

func_getSnapShot

func_snapShotConvert2Base64

func_checkInternetStatus
if [ $? -eq 0 ]; then func_command2Controller '$$IMAGE_FAILURE*' $SERIAL_PORT_DATA_DUMP && func_SystemHalt && exit 1; fi

func_sendSnapShot2Server

func_check_backlog && func_command2Controller $COMMAND_TO_CONTROLLER $SERIAL_PORT_DATA_DUMP && func_postICTLog_to_server && func_SystemHalt