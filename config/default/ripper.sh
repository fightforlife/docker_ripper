#!/bin/bash

set -euo pipefail

RIPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOGFILE="/config/Ripper.log"
DEBUG=${DEBUG:-"False"}
if [ 'true' == ${DEBUG,,} ]; then
  set -xo verbose
fi

SEND_NOTIFICATION=${SEND_NOTIFICATION:-"n"}

# Startup Info
echo "$(date "+%d.%m.%Y %T") : Starting Ripper. Optical Discs will be detected and ripped within 60 seconds."

# Separate Raw Rip and Finished Rip Folders for DVDs and BluRays
# Raw Rips go in the usual folder structure
# Finished Rips are moved to a "finished" folder in it's respective STORAGE folder
SEPARATERAWFINISH="true"

# Paths
STORAGE_CD="/out/Ripper/CD"
STORAGE_DATA="/out/Ripper/DATA"
STORAGE_DVD="/out/Ripper/DVD"
STORAGE_BD="/out/Ripper/BluRay"
DRIVE="/dev/sr0"

BAD_THRESHOLD=5
BAD_RESPONSE=0

ejectDrive() {
  if eject -v $DRIVE | grep 'whole-disk' >>/dev/null; then
    echo "First attempt at Ejecting Disk Succeeded"
    exit 1
  else
    echo "First Attempt At Ejecting Disk Failed. Attempting Alternative Method." >>$LOGFILE 2>&1
    echo "$(date "+%d.%m.%Y %T") : First Attempt At Ejecting Disk Failed. Trying Alternative Method."
    sleep 2
    sdparm --command=unlock $DRIVE
    sleep 1
    sdparm --command=eject $DRIVE
    exit 1
  fi
}

notify() {
  if [[ "y" == "${SEND_NOTIFICATION,,}" ]]; then
    SUBJECT="[DOCKER-RIPPER] rip completed"
    BODY= "rip completed. See logs for more details."
    [[ -n ${EMAIL_SENDER} ]] && notifications email --subject ${SUBJECT} --body ${BODY} --recipients ${EMAIL_RECIPIENTS}
    [[ -n ${PUSHOVER_APP_TOKEN} ]] && notifications pushover --subject ${SUBJECT} --body ${BODY}
    [[ -n ${PUSHBULLET_APP_TOKEN} ]] && notifications pushbullet --subject ${SUBJECT} --body ${BODY}
  fi
}

changePerms() {
  newPerm=${NUID:-$UID}":"${NGID:-$GROUPS}
  if [[ ":" == "${newPerm}" ]]; then
    newPerm=nobody:users
  fi
  chown -R ${newPerm} "$1" && chmod -R g+rw "$1"
}

# True is always true, thus loop indefinitely
while true; do
  # delete MakeMKV temp files
  cwd=$(pwd)
  cd /tmp
  rm -r *.tmp >/dev/null 2>&1 || true
  cd $cwd

  # get disk info through makemkv and pass output to INFO
  INFO=$"$(makemkvcon -r --cache=1 info disc:9999 | grep DRV:0)"
  # check INFO for optical disk
  EMPTY=$(echo $INFO | grep -o 'DRV:0,0,999,0,"') || true
  OPEN=$(echo $INFO | grep -o 'DRV:0,1,999,0,"') || true
  LOADING=$(echo $INFO | grep -o 'DRV:0,3,999,0,"') || true
  BD1=$(echo $INFO | grep -o 'DRV:0,2,999,12,"') || true
  BD2=$(echo $INFO | grep -o 'DRV:0,2,999,28,"') || true
  DVD=$(echo $INFO | grep -o 'DRV:0,2,999,1,"') || true
  CD1=$(echo $INFO | grep -o 'DRV:0,2,999,0,"') || true
  CD2=$(echo $INFO | grep -o '","","'$DRIVE'"') || true

  # Check for trouble and respond if found
  EXPECTED="${EMPTY}${OPEN}${LOADING}${BD1}${BD2}${DVD}${CD1}${CD2}"
  if [ "x$EXPECTED" == 'x' ]; then
    echo "$(date "+%d.%m.%Y %T") : Unexpected makemkvcon output: $INFO"
    ((BAD_RESPONSE++))
  else
    BAD_RESPONSE=0
  fi
  if (($BAD_RESPONSE >= $BAD_THRESHOLD)); then
    echo "$(date "+%d.%m.%Y %T") : Too many errors, ejecting disk and aborting"
    # Run makemkvcon once more with full output, to potentially aid in debugging
    makemkvcon -r --cache=1 info disc:9999
    notify
    ejectDrive
  fi

  # if [ $EMPTY = 'DRV:0,0,999,0,"' ]; then
  #  echo "$(date "+%d.%m.%Y %T") : No Disc"; &>/dev/null
  # fi
  if [ "$OPEN" = 'DRV:0,1,999,0,"' ]; then
    echo "$(date "+%d.%m.%Y %T") : Disk tray open"
  fi
  if [ "$LOADING" = 'DRV:0,3,999,0,"' ]; then
    echo "$(date "+%d.%m.%Y %T") : Disc still loading"
  fi

  if [ "$BD1" = 'DRV:0,2,999,12,"' ] || [ "$BD2" = 'DRV:0,2,999,28,"' ]; then
    DISKLABEL=$(echo $INFO | grep -o -P '(?<=",").*(?=",")') || true
    BDPATH="$STORAGE_BD"/"$DISKLABEL"
    BLURAYNUM=$(echo $INFO | grep $DRIVE | cut -c5) || true
    mkdir -p "$BDPATH"
    ALT_RIP="${RIPPER_DIR}/BLURAYrip.sh"
    if [[ -f $ALT_RIP && -x $ALT_RIP ]]; then
      echo "$(date "+%d.%m.%Y %T") : BluRay detected: Executing $ALT_RIP"
      $ALT_RIP "$BLURAYNUM" "$BDPATH" "$LOGFILE"
    else
      # BluRay/MKV
      echo "$(date "+%d.%m.%Y %T") : BluRay detected: Saving MKV"
      makemkvcon --profile=/config/default.mmcp.xml -r --decrypt --minlength=600 mkv disc:"$BLURAYNUM" all "$BDPATH" >>$LOGFILE 2>&1
    fi
    if [ "$SEPARATERAWFINISH" = 'true' ]; then
      BDFINISH="$STORAGE_BD"/finished/
      mv -v "$BDPATH" "$BDFINISH"
    fi
    echo "$(date "+%d.%m.%Y %T") : Done! Ejecting Disk"
    notify
    ejectDrive
    # permissions
    changePerms "$STORAGE_BD"
  fi

  if [ "$DVD" = 'DRV:0,2,999,1,"' ]; then
    DISKLABEL=$(echo $INFO | grep -o -P '(?<=",").*(?=",")') || true
    DVDPATH="$STORAGE_DVD"/"$DISKLABEL"
    DVDNUM=$(echo $INFO | grep $DRIVE | cut -c5) || true
    mkdir -p "$DVDPATH"
    ALT_RIP="${RIPPER_DIR}/DVDrip.sh"
    if [[ -f $ALT_RIP && -x $ALT_RIP ]]; then
      echo "$(date "+%d.%m.%Y %T") : DVD detected: Executing $ALT_RIP"
      $ALT_RIP "$DVDNUM" "$DVDPATH" "$LOGFILE"
    else
      # DVD/MKV
      echo "$(date "+%d.%m.%Y %T") : DVD detected: Saving MKV"
      makemkvcon --profile=/config/default.mmcp.xml -r --decrypt --minlength=600 mkv disc:"$DVDNUM" all "$DVDPATH" >>$LOGFILE 2>&1
    fi
    if [ "$SEPARATERAWFINISH" = 'true' ]; then
      DVDFINISH="$STORAGE_DVD"/finished/
      mv -v "$DVDPATH" "$DVDFINISH"
    fi
    echo "$(date "+%d.%m.%Y %T") : Done! Ejecting Disk"
    notify
    ejectDrive
    # permissions
    changePerms "$STORAGE_DVD"
  fi

  if [ "$CD1" = 'DRV:0,2,999,0,"' ]; then
    if [ "$CD2" = '","","'$DRIVE'"' ]; then
      ALT_RIP="${RIPPER_DIR}/CDrip.sh"
      if [[ -f $ALT_RIP && -x $ALT_RIP ]]; then
        echo "$(date "+%d.%m.%Y %T") : CD detected: Executing $ALT_RIP"
        $ALT_RIP "$DRIVE" "$STORAGE_CD" "$LOGFILE"
      else
        # MP3 & FLAC
        echo "$(date "+%d.%m.%Y %T") : CD detected: Saving MP3 and FLAC"
        /usr/bin/abcde -d "$DRIVE" -c /config/abcde.conf -N -x -l >>$LOGFILE 2>&1
      fi
      echo "$(date "+%d.%m.%Y %T") : Done! Ejecting Disk"
      notify
      ejectDrive
      # permissions
      changePerms "$STORAGE_CD"
    else
      DISKLABEL=$(echo $INFO | grep $DRIVE | grep -o -P '(?<=",").*(?=",")') || true
      ISOPATH="$STORAGE_DATA"/"$DISKLABEL"/"$DISKLABEL".iso
      mkdir -p "$STORAGE_DATA"/"$DISKLABEL"
      ALT_RIP="${RIPPER_DIR}/DATArip.sh"
      if [[ -f $ALT_RIP && -x $ALT_RIP ]]; then
        echo "$(date "+%d.%m.%Y %T") : Data-Disk detected: Executing $ALT_RIP"
        $ALT_RIP "$DRIVE" "$ISOPATH" "$LOGFILE"
      else
        # ISO
        echo "$(date "+%d.%m.%Y %T") : Data-Disk detected: Saving ISO"
        ddrescue $DRIVE "$ISOPATH" >>$LOGFILE 2>&1
      fi
      echo "$(date "+%d.%m.%Y %T") : Done! Ejecting Disk"
      notify
      ejectDrive
      # permissions
      changePerms "$STORAGE_DATA"
    fi
  fi
  # Wait a minute
  sleep 1m
done
