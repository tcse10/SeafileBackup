#!/bin/bash
#

source backup-seafile.conf

# write backup to tape
backup2tape(){
  $MT -f $tapedrive setblk 0
  $MT -f $tapedrive status
  totalsize=$(du -csh $datadir | tail -1 | cut -f1)
  echo "${totalsize}"
  $TAR -cvpf - $datadir | \
    $GPG --encrypt --recipient $recipient --compress-algo none | \
    $MBUFFER -m 3G -P 95% -s 256k -f -o $tapedrive -A "echo next tape; $MT -f $tapedrive eject ; read a < /dev/tty"
  $MT -f $tapedrive rewind
  $MT -f $tapedrive offline

}

dbbackup(){
  # looking for 3 days old database backups and delete them 
  find $dbbackupdir -maxdepth 1 -mtime +3 -type f -delete
  
  # create Database Backup
  $MYSQLDUMP -h $mysqlhost -u $username -p$password --opt ccnet-db > $dbbackupdir/ccnet-db.sql.`date +"%Y-%m-%d-%H-%M-%S"` 
  $MYSQLDUMP -h $mysqlhost -u $username -p$password --opt seafile-db > $dbbackupdir/seafile-db.sql.`date +"%Y-%m-%d-%H-%M-%S"` 
  $MYSQLDUMP -h $mysqlhost -u $username -p$password --opt seahub-db > $dbbackupdir/seahub-db.sql.`date +"%Y-%m-%d-%H-%M-%S"` 
}
 
# restore from tape
restore(){
  restoreDir=$1
  restorePW=$2
  $MT -f $tapedrive rewind
  $MT -f $tapedrive setblk 0
  $MT -f $tapedrive status
  $MBUFFER -m 3G -p 5% -s 256k -f -i $tapedrive -A "echo next tape; $MT -f $tapedrive eject ; read a < /dev/tty" | \
    $GPG --passphrase $restorePW --batch --decrypt | \
    $TAR -xf - --directory=$restoreDir
}

if [[ $1 == "backup" ]]; then
  # Make sure log dir exits
  [ ! -d $LOGBASE ] && $MKDIR -p $LOGBASE

  # log on 
  exec 3>&1 4>&2
  trap 'exec 2>&4 1>&3' 0 1 2 3
  exec 1>>${LOGFIILE} 2>&1
  
  # create a full backup of complete seafile files
  dbbackup
  backup2tape

elif [[ $1 == "restore" && -n "$2" ]]; then
  #get pgp credentials
  stty_orig=`stty -g` # save original terminal setting.
  stty -echo          # turn-off echoing.
  read -p "pgp Password: " pgpPassword
  stty $stty_orig     # restore terminal setting.

  echo "restore to $2 read a < /dev/tty"
  restore $2 $pgpPassword
fi
