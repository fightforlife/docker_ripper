#!/bin/bash

set -euo pipefail

chmod +x $0
NOTIFICATION_SETTINGS=/root/python-simple-notifications/simple_notifications/simple_notifications_config.py

# copy default script
if [[ ! -f /config/ripper.sh ]]; then
  cp /ripper/ripper.sh /config/ripper.sh
fi

#Copy conf if not present.
if [[ ! -f /config/abcde.conf ]]; then
  cp /ripper/abcde.conf /config/abcde.conf
fi

TZ=${TZ:-'America/Chicago'}
NUID=${NUID:-99}
NGID=${NGID:-100}
DEBUG=${DEBUG:-"false"}
if [ 'true' == "${DEBUG,,}" ]; then
  set -xo verbose
fi

##Functions
setTimeZone() {
  [[ ${TZ} == $(cat /etc/timezone) ]] && return
  echo "Setting timezone to ${TZ}"
  ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
  dpkg-reconfigure -fnoninteractive tzdata
}

getVersion() {
  echo "latest version:   $(curl -s http://www.makemkv.com/download/ | grep -Eom1 'MakeMKV v?1.[0-9]+\.[0-9]+')"
  echo "installed version: $(makemkvcon info | head -n1)"
}

setNotificationConfig() {
  # Email notification parameters
  [[ -n ${EMAIL_SENDER} ]] && sed -i "s/= 'YOUR_EMAIL'/= '${EMAIL_SENDER}'/" ${NOTIFICATION_SETTINGS}
  [[ -n ${EMAIL_PASSWORD} ]] && sed -i "s/= 'YOUR_PASSWORD'/= '${EMAIL_PASSWORD}'/" ${NOTIFICATION_SETTINGS}
  [[ -n ${EMAIL_SERVER} ]] && sed -i "s/= 'smtp.gmail.com'/= '${EMAIL_SERVER}'/" ${NOTIFICATION_SETTINGS}
  [[ -n ${EMAIL_SERVER_PORT} ]] && sed -i "s/= '587'/= '${EMAIL_SERVER_PORT}'/" ${NOTIFICATION_SETTINGS}
  [[ -n ${EMAIL_DEBUG_LEVEL} ]] && sed -i "s/= '0'/= '${EMAIL_DEBUG_LEVEL}'/" ${NOTIFICATION_SETTINGS}

  # Push notification parameters (Pushover)
  [[ -n ${PUSHOVER_APP_TOKEN} ]] && sed -i "s/PUSHOVER_APP_TOKEN = 'YOUR_APP_TOKEN'/PUSHOVER_APP_TOKEN = '${PUSHOVER_APP_TOKEN}'/" ${NOTIFICATION_SETTINGS}
  [[ -n ${USER_KEY} ]] && sed -i "s/= 'YOUR_USER_KEY'/= '${USER_KEY}'/" ${NOTIFICATION_SETTINGS}

  # Push notification parameters (Pushbullet)
  [[ -n ${PUSHBULLET_APP_TOKEN} ]] && sed -i "s/PUSHBULLET_APP_TOKEN = 'YOUR_APP_TOKEN'/PUSHBULLET_APP_TOKEN = '${PUSHBULLET_APP_TOKEN}'/" ${NOTIFICATION_SETTINGS}
  cd /root/python-simple-notifications
  pip3 install . 2>&1
}

#Main
setTimeZone
getVersion
setNotificationConfig

[[ $(id -u nobody) -ne ${NUID:-99} ]] && echo "setting uid as ${NUID}" && usermod -u ${NUID:-99} nobody
[[ $(id -g nobody) -ne ${NGID:-100} ]] && echo "setting gid as ${NGID}" && usermod -g ${NGID:-100} nobody

# fetching MakeMKV beta key
KEY=$(curl --silent 'https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053' | grep -oP 'T-[\w\d@]{66}')
MKV_KEY=${MKV_KEY:-${KEY}}

# copy default settings
mkdir -p /root/.MakeMKV
if [[ ! -f /config/settings.conf ]] && [[ -n ${MKV_KEY} ]]; then
  echo "app_Key = \"${MKV_KEY}\"" >/config/settings.conf
  echo "No settings.conf. writing key to file."
  cp /config/settings.conf /root/.MakeMKV/settings.conf
fi

# Updating Key if needed
if [[ $(grep -c ${MKV_KEY} /config/settings.conf) -eq 0 ]]; then
  echo "app_Key = \"${MKV_KEY}\"" >/config/settings.conf
  echo "Found settings.conf. Replacing beta key file."
  cp /config/settings.conf /root/.MakeMKV/settings.conf
fi

# permissions
for f in /config/*.sh /ripper/*.sh
do chmod +x ${f}
done
chmod +x /web/web.py

chown -R nobody:users /config
chmod -R g+rw /config

chmod +x /config/ripper.sh
#makemkvcon reg

supervisorctl start ripper
