#!/bin/bash

SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`
ENV_FILE=$SCRIPTPATH/.env
if [ ! -f "$ENV_FILE" ]; then
    echo "A '$ENV_FILE' file is needed." >&3
    exit
fi

export $(grep -v '^#' $ENV_FILE | xargs -d '\n')

MAX_LOG_SIZE=10485760 # 20MB
DATE="`date +%Y-%m-%d`"
BACKUP_SUFFIX="`date +%Y%m%d`"
EXPECT_FILE="/usr/bin/expect"
FREE_SPACE_GB="`df --output=avail -h . | sed '1d;s/[^0-9]//g'`"

if [ ! -f "$LOG_FILE" ]; then
    touch $LOG_FILE
fi

LOG_FILE_SIZE=`du -b $LOG_FILE | tr -s '\t' ' ' | cut -d' ' -f1`
if [ $LOG_FILE_SIZE -gt $MAX_LOG_SIZE ];then   
    mv $LOG_FILE $LOG_FILE.$BACKUP_SUFFIX
    touch $LOG_FILE
fi

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>$LOG_FILE 2>&1

if [ ! -f "$EXPECT_FILE" ]; then
    echo "$EXPECT_FILE does not exist or is not installed." >&3
    echo "EXECUTE: $ sudo apt-get install expect" >&3
    exit
fi

if [ $FREE_SPACE_GB -lt $MINIMAL_FREE_SPACE_GB ]; then
    echo "There is not enough space on the disk." >&3
    echo "Actual space: $FREE_SPACE_GB GB." >&3
    echo "Minimal space: $MINIMAL_FREE_SPACE_GB GB." >&3
    exit
fi

echo "$(date +%Y-%m-%d:%H:%M:%S): ##############################"

if [ $BACKUP_SSH == 'true' ]; then

    if [ ! -d "$DESTINATION_LOCAL_PATH" ]; then
        echo "Folder $DESTINATION_LOCAL_PATH does not exist." >&3
        exit
    fi

    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
    echo "$(date +%Y-%m-%d:%H:%M:%S): Starting SSH incremental backup from '$SSH_HOST:$SOURCE_SERVER_PATH' to '$DESTINATION_LOCAL_PATH'"
    COMMAND="rsync --exclude 'cache' --exclude 'DEV/cache' --prune-empty-dirs --exclude '*.log' --exclude '*.wpress' --exclude '*.gz' --exclude '*.old' -vhrzbP --suffix=_BKP_$BACKUP_SUFFIX -e ssh $SSH_USERNAME@$SSH_HOST:$SOURCE_SERVER_PATH $DESTINATION_LOCAL_PATH"

    /usr/bin/expect << EOD
    set timeout -1
    spawn ${COMMAND}
    expect "*?assword:"
    send "${SSH_PASSWORD}\r"
    expect eof
EOD

    echo "$(date +%Y-%m-%d:%H:%M:%S): SSH End."
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
else 
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
    echo "$(date +%Y-%m-%d:%H:%M:%S): SSH backups is Disabled."
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
fi

if [ $BACKUP_DB == 'true' ]; then
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
    echo "$(date +%Y-%m-%d:%H:%M:%S): Starting DB dump backup."
    BACKUP_FILE_NAME="$DB_DATABASE-backup-$BACKUP_SUFFIX.sql.gz"

    /usr/bin/expect << EOD
    set timeout -1
    spawn ssh ${SSH_USERNAME}@${SSH_HOST} "mysqldump --user=${DB_USER} --password=${DB_PASS} ${DB_DATABASE} | gzip -9 > ${BACKUP_FILE_NAME}"
    expect "*?assword:"
    send "${SSH_PASSWORD}\r"
    expect eof
EOD

    COMMAND="rsync -vhrzbP -e ssh $SSH_USERNAME@$SSH_HOST:$BACKUP_FILE_NAME $DB_DESTINATION_PATH"
/usr/bin/expect << EOD
    set timeout -1
    spawn ${COMMAND}
    expect "*?assword:"
    send "${SSH_PASSWORD}\r"
    expect eof
EOD

    /usr/bin/expect << EOD
    set timeout -1
    spawn ssh ${SSH_USERNAME}@${SSH_HOST} "rm ${BACKUP_FILE_NAME}"
    expect "*?assword:"
    send "${SSH_PASSWORD}\r"
    expect eof
EOD

    echo "$(date +%Y-%m-%d:%H:%M:%S): DB End."
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
else 
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
    echo "$(date +%Y-%m-%d:%H:%M:%S): DB backups is Disabled."
    echo "$(date +%Y-%m-%d:%H:%M:%S): ---------------------------------------"
fi

echo "$(date +%Y-%m-%d:%H:%M:%S): ##############################"
