#!/bin/bash
TZ=${TZ:-'Europe/Berlin'}
NUID=${NUID:-1000}
NGID=${NGID:-1000}
DEBUG=${DEBUG:-"false"}
# copy default files if not already there
if [[ ! -f /config/abcde.conf ]]; then
 echo "/config/abcde.conf, providing default file"
 cp /config/default/abcde.conf /config/abcde.conf
fi
if [[ ! -f /config/default.mmcp.xml ]]; then
 echo "/config/default.mmcp.xml, providing default file"
 cp /config/default/default.mmcp.xml /config/default.mmcp.xml
fi
if [[ ! -f /config/ripper.sh ]]; then
 echo "/config/ripper.sh, providing default file"
 cp /config/default/ripper.sh /config/ripper.sh
fi
if [[ ! -f /config/settings.conf ]]; then
 echo "/config/settings.conf , providing default file"
 cp /config/default/settings.conf /config/settings.conf
fi

# Get beta key if no key provided
if [[ ! -z $MKV_KEY ]]; then
 echo "MakeMKV key was provided via MKV_KEY: "$MKV_KEY""
elif [[ -z $MKV_KEY ]]; then
 echo "MakeMKV key was not provided via MKV_KEY, grabbed beta key from Website"
 MKV_KEY=$(curl --silent 'https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053' | grep -oP 'T-[\w\d@]{66}')
 if [[ -z $MKV_KEY ]];  then
  echo "Fetching makeMKV beta key was not successfull, stopping init."
  exit
 elif [[ ! -z $MKV_KEY ]]; then
  echo "MakeMKV key was successfully fetched: "$MKV_KEY""
 fi
fi

# Updating current key if needed
if [[ $(grep -c ${MKV_KEY} /config/settings.conf) -eq 0 ]]; then
  sed -i -r 's/^(app_Key =).*/app_Key = "'"$MKV_KEY"'"/' /config/settings.conf
  echo "Updated settings.conf with new key!"
fi
mkdir -p ~/.MakeMKV
cp -f /config/settings.conf ~/.MakeMKV/settings.conf
makemkvcon reg "" 2>/dev/null || true

echo "Starting the ripper loop"
/config/ripper.sh