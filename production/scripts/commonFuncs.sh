# STATIC FILE PATHS
ICTNO=$(cat < /home/qdnet/production/config/ictnumber)
ICT_LOG="/home/qdnet/production/logs/$ICTNO.log"
HOURLY_SNAPSHOT_PATH="/home/qdnet/production/hourlySnapShots/"
HOURLY_SNAPSHOT_BACKLOG_PATH="/home/qdnet/production/hourlySnapShotsBacklog/"
HOURLY_SNAPSHOT_BACKLOG_JPGS="/home/qdnet/production/hourlySnapShotsBacklog/*.jpg"

func_updateCntrlrWithLatestDt() {
    echo "$(date) : UPDATING CONTROLLER WITH LATEST DATE-TIME !!!" >> $ICT_LOG
    CURN_YYYYMMDD_HHMMSS=`date +%Y%m%d,%H%M%S`
    COMMAND_TO_CONTROLLER="\$\$TIME=$CURN_YYYYMMDD_HHMMSS*";
    func_command2Controller $COMMAND_TO_CONTROLLER $SERIAL_PORT_DATA_DUMP
}

func_fetchDtFromController() {
    echo "REQUESTING DATE-TIME FROM CONTROLLER !!!" >> $ICT_LOG
    # IF SYSTEM WAS NOT ABLE TO SYNC TIME FROM INTERNET, FETCH THE DATE-TIME, THE CONTROLLER IS MAINTAINING...
    func_command2Controller '$$REQUEST_DT*' $SERIAL_PORT_DATA_DUMP
    sleep 1s;    
    REQUEST_DT=$(cat $SERIAL_PORT_DATA_DUMP | sed -e 's/[\r\n]//g')
    REQUEST_DT=( $(echo $REQUEST_DT | sed -r 's/TIME Received = ([0-9]+).([0-9]+).([0-9]+).([0-9]+).([0-9]+).([0-9]+)/\1 \2 \3 \4 \5 \6/g') )
    REQUEST_DT_LEN=${#REQUEST_DT[@]}
    if [ "$REQUEST_DT_LEN" -eq "0" ]; then echo "NO DATE-TIME INFO FOUND FROM CONTROLLER. RETURNING !!!" >> $ICT_LOG && return 0; fi
    if [ "$REQUEST_DT_LEN" -ne "6" ]; then echo "CONTROLLER DATE-TIME. INVALID ELEMENTS = $REQUEST_DT_LEN RETURNING !!!" >> $ICT_LOG && return 0; fi
    if [ "${REQUEST_DT[2]}" -eq "2000" ]; then echo "CONTROLLER DATE-TIME. INVALID YEAR : [${REQUEST_DT[2]}] !!!" >> $ICT_LOG && return 0; fi
    printf -v CNTRL_DATE "%d-%02d-%02d" "${REQUEST_DT[2]}" "${REQUEST_DT[1]}" "${REQUEST_DT[0]}"
    printf -v CNTRL_TIME "%02d:%02d:%02d" "${REQUEST_DT[3]}" "${REQUEST_DT[4]}" "${REQUEST_DT[4]}"
    echo "MANUALLY SETTING SYSTEM DATE-TIME !!! $CNTRL_DATE $CNTRL_TIME" >> $ICT_LOG
    SET_DATE_TIME_MANUAL=$(date -s "$CNTRL_DATE $CNTRL_TIME")
    echo "SYSTEM DATE-TIME SET CONFIRMATION - $SET_DATE_TIME_MANUAL !!!" >> $ICT_LOG
    return 1
}

func_buildImgNamePattern() {
    IMAGE_DATE_HOUR=$(date +"%Y%m%d%H")
    IMAGE_DATE=$(date +"%Y%m%d")
    IMAGE_TIME=$(date +"%H%M%S")

    IMAGE_FILE_NAME=$ICTNO"_"$IMAGE_DATE_HOUR".jpg"
    IMAGE_RAW_FILE_NAME="RAW_"$ICTNO"_"$IMAGE_DATE_HOUR".jpg"
    IMAGE_FILE_PATH="$HOURLY_SNAPSHOT_PATH$IMAGE_FILE_NAME"
    IMAGE_RAW_FILE_PATH="$HOURLY_SNAPSHOT_PATH$IMAGE_RAW_FILE_NAME"
    # BUILD THE PARAM DEFINTION TO POST TO SERVER
    PARAMS="\$,$ICTNO,$ICTNO,0,0,$IMAGE_DATE,$IMAGE_TIME,0,0,0,0,0,0,A,0,0,0,0,0,0,1,0,*"    
}

func_checkInternetStatus() {
    ntries=0
    echo "$(date) : TRYING INTERNET CONNECTION !!!" >> $ICT_LOG;
    while [ $ntries -lt 5 ]
        do
            INTERNET_CONN=$(curl -s --max-time 3 -L -I -X GET http://www.google.com)
            if [ "$INTERNET_CONN" != "" ]; then
                echo "$(date) : INTERNET CONNECTION : SUCCESS[$ntries] !!!" >> $ICT_LOG;
                return 1
            fi
            ntries=`expr $ntries + 1`; sleep 5s; continue
        done
    echo "$(date) : INTERNET CONNECTION : FAILED[$ntries] !!!" >> $ICT_LOG
    return 0
}

func_check_camera_online() {
    CAMERA_STATUS=0
    ntries=0
    while [ $ntries -lt 5 ]
        do
            sudo ping -w 1 -c 1 192.168.1.250 > /dev/null
            if [ $? -ne 0 ]; then ntries=`expr $ntries + 1`; sleep 1s; continue; fi
            echo "$(date) : CAMERA CONNECTION : SUCCESS[$ntries] !!!" >> $ICT_LOG
            CAMERA_STATUS=1
            return 1
      done
    echo "$(date) : CAMERA CONNECTION : FAILED[$ntries] !!!" >> $ICT_LOG
    return 0
}

func_getSnapShot() {
    COMMAND_TO_CONTROLLER='$$IMAGE_FAILURE*'; # DEFAULT COMMAND STATE
    if [ $CAMERA_STATUS -eq 0 ]; then return 0; fi
    if [ -f $IMAGE_FILE_PATH ]; then echo "$(date) : func_getSnapShot() - BASE64 FILE ALREADY CREATED/AVAILABLE - RETURNING !!!" >> $ICT_LOG; return 1; fi
    if [ -f $IMAGE_RAW_FILE_PATH ]; then echo "$(date) : HOURLY IMAGE FILE ALREADY CAPTURED/EXISTS - RETURNING !!!" >> $ICT_LOG; return 1; fi
    echo "$(date) : CREATING RAW NEW HOURLY IMAGE - $IMAGE_RAW_FILE_PATH !!!" >> $ICT_LOG
    ffmpeg -y -hide_banner -rtsp_transport tcp -i "rtsp://admin:admin12345@192.168.1.250:554/cam/realmonitor?channel=1&subtype=0&uincast=true" -vframes 1 -nostdin -loglevel panic -strftime 1 "$IMAGE_RAW_FILE_PATH"
    if [ -f $IMAGE_RAW_FILE_PATH ]; then echo "$(date) : CAMERA RAW IMAGE CAPTURE - SUCCESSFULL !!!" >> $ICT_LOG; return 1; fi
    echo "$(date) : CAMERA RAW IMAGE CAPTURE - FAILED !!! CHECK FFMPEG COMMAND" >> $ICT_LOG
    return 0
}

func_snapShotConvert2Base64() {
    # FIRST CHECK IF RAW IMAGE FILE IS AVAILABLE/CREATED
    if [ -f $IMAGE_FILE_PATH ]; then echo "$(date) : BASE64 FILE ALREADY CREATED/AVAILABLE - RETURNING !!!" >> $ICT_LOG; return 1; fi
    if [ ! -f $IMAGE_RAW_FILE_PATH ]; then echo "$(date) : RAW IMAGE FILE NOT FOUND [$IMAGE_RAW_FILE_PATH] - RETURNING !!!" >> $ICT_LOG; return 0; fi
    IMAGE_BASE64="$(cat $IMAGE_RAW_FILE_PATH | base64)"
    echo $PARAMS > $IMAGE_FILE_PATH
    VOLTAGE_CURRENT_DATA=$(cat $VOLTAGE_CURRENT_READINGS) #DUMP CAPTURED DATA
    echo "$VOLTAGE_CURRENT_DATA" >> $IMAGE_FILE_PATH
    echo $IMAGE_BASE64 >> $IMAGE_FILE_PATH
    if [ -f $IMAGE_FILE_PATH ]; then 
        echo "$(date) : BASE64 IMAGE CREATION : SUCCESSFULL !!!" >> $ICT_LOG;
        `rm -f $IMAGE_RAW_FILE_PATH`
        if [ ! -f $IMAGE_RAW_FILE_PATH ]; then echo "$(date) : RAW IMAGE FILE DELETION [$IMAGE_RAW_FILE_PATH] - SUCCESSFULL !!!" >> $ICT_LOG; fi
        return 1;
    fi
    COMMAND_TO_CONTROLLER='$$IMAGE_FAILURE*'; # DEFAULT COMMAND STATE
    echo "$(date) : BASE64 IMAGE [$IMAGE_FILE_PATH] : CREATION FAILED/NOT FOUND !!!" >> $ICT_LOG
    return 0
}

func_postICTLog_to_server() {
    echo "$(date) : SENDING LOG DATA TO SERVER !!!" >> $ICT_LOG
    STORE_RESPONSE=$(curl -s --max-time 15 -F "ICT_LOG_FILE=@$ICT_LOG" "http://ictsolarcam.qdnet.com/cgi-bin/imgStore/ictLogDump.pl?$ICTNO")
    CAT_FILE=$(cat /dev/null > $ICT_LOG)
}

func_post_to_server() {
    echo "$(date) : INITIATING POST TO SERVER !!!" >> $ICT_LOG
    RESPONSE=$(curl -s --max-time 15 -F "ICT_HOURLY_IMAGE=@$1" "$2")
    if [ "$RESPONSE" = "****SUCCESS****" ] ; then return 1; fi
    return 0
}

func_sendSnapShot2Server() {
    if [ ! -f $IMAGE_FILE_PATH ]; then echo "$(date) : NO IMAGE TO POST TO SERVER - RETURNING !!!" >> $ICT_LOG; return 0; fi
    POST_URL="http://ictsolarcam.qdnet.com/cgi-bin/imgStore/httpimagV1.pl?post"$ICTNO"SnapShot"
    func_post_to_server "$IMAGE_FILE_PATH" "$POST_URL"
    if [ $? -eq 1 ]; then
        echo "$(date) : IMAGE POST SUCCESS !!!" >> $ICT_LOG
        COMMAND_TO_CONTROLLER='$$IMAGE_SUCCESS*'
        `rm -f $IMAGE_FILE_PATH`;
        return 1
    fi
    echo "$(date) : IMAGE POST FAILED !!!" >> $ICT_LOG
    COMMAND_TO_CONTROLLER='$$IMAGE_FAILURE*'
    return 0
}

func_checkCountOfPendingSnapShots() {
    BACKLOG_SNAPSHOT_FILES_COUNT=`ls $HOURLY_SNAPSHOT_BACKLOG_PATH | wc -l`
    if [ $BACKLOG_SNAPSHOT_FILES_COUNT -eq 0 ]; then echo "$(date) : NO SNAPSHOTs FOUND IN hourlySnapShotsBacklog DIRECTORY !!!" >> $ICT_LOG; return 0; fi
    echo "$(date) : $BACKLOG_SNAPSHOT_FILES_COUNT SNAPSHOTs FOUND IN hourlySnapShots DIRECTORY !!!" >> $ICT_LOG
    return 1
}

func_postBacklogSnapShots() {
    BACKLOG_SNAPSHOT_FILES_LIST=`ls -1 $HOURLY_SNAPSHOT_BACKLOG_JPGS`
    for eachSnapShotFile in $BACKLOG_SNAPSHOT_FILES_LIST
        do
            POST_URL="http://ictsolarcam.qdnet.com/cgi-bin/imgStore/httpimagV1.pl?post"$ICTNO"SnapShotBacklog"
            func_post_to_server "$eachSnapShotFile" "$POST_URL"
            if [ $? -eq 1 ]; then # IF NO INTERNET... EXIT THE PROGRAM
                echo "$(date) : BACKLOG POSTING - SUCCESSFULL !!! [$eachSnapShotFile]" >> $ICT_LOG
                `rm -f $eachSnapShotFile`;
                continue
            fi
            echo "$(date) : BACKLOG POSTING - FAILED !!! [$eachSnapShotFile]" >> $ICT_LOG
        done
}

func_check_backlog() {
    func_checkCountOfPendingSnapShots
    if [ $? -eq 0 ]; then return; fi
    func_postBacklogSnapShots
}

func_SystemHalt() {
    echo "$(date) : HALTING SYSTEM !!!" >> $ICT_LOG; 
    `sudo shutdown -h now`
}

func_CheckInternetClock() {
    # CHECK DONGLE TYPE CONNECTED...
    local USB_TYPE=""
    local USB_0_FIND=""
    local USB_ENC_FIND=""
    local usb_inet_count=""
    USB_0_FIND=$(/sbin/ifconfig -s -a | grep "usb")
    USB_ENC_FIND=$(/sbin/ifconfig -s -a | grep "enx0c5b8")
    if [ "$USB_0_FIND" != "" ]; then
        USB_TYPE="usb0"
    elif [ "$USB_ENC_FIND" != "" ]; then
        USB_TYPE="enx0c5b8f279a64"
    fi
    if [ "$USB_TYPE" = "" ]; then echo "$(date) : WIFI USB DEVICE NOT DETECTED !!!" >> $ICT_LOG; return 0; fi
    usb_inet_count=$(/sbin/ifconfig $USB_TYPE | grep inet | wc -l)
    if [ $usb_inet_count -le 1 ]; then echo "$(date) : WIFI USB - IPADDRESS NOT GENERATED !!!" >> $ICT_LOG; return 0; fi
    echo "$(date) : WIFI USB [$USB_TYPE]  - $usb_inet_count INET ADRRESS ENTRIES FOUND !!!" >> $ICT_LOG
    synctries=0
    while [ $synctries -lt 5 ]
        do
            timedatectl_syncd=$(timedatectl | grep "System clock synchronized: yes")
            if [ "$timedatectl_syncd" = "" ]; then echo "$(date) : CLOCK SYNCHRONISATION - FAILED[$synctries] !!! " >> $ICT_LOG; synctries=`expr $synctries + 1`; sleep 5s; continue; fi
            echo "$(date) : CLOCK SYNCHRONISATION - SUCCESSFULL !!!" >> $ICT_LOG
            return 1
      done
      echo "$(date) : CLOCK SYNCHRONISATION - COMPLETELY FAILED [25secs] !!!" >> $ICT_LOG
      # Since clock synchronisation has failed... Now fetch the Date-Time from teh Controller...
      return 0
}

func_IsTimeSyncd() {
    func_CheckInternetClock
    if [ $? -eq 1 ]; then
        func_updateCntrlrWithLatestDt
        return 1
    fi
    func_fetchDtFromController;
    return $?
}
