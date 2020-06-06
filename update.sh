#!/bin/bash
set -e

# If no version requested get latest
if [ "$1" == "" ];
then
  LATESTSTABLE=$(curl -f -L  https://updates.jenkins.io/stable/latestCore.txt | awk -F'.' '{print $1"."$2}')
  VERSION="stable-${LATESTSTABLE}"
  echo "[ INFO  ] Latest stable version : ${VERSION}"
else
  VERSION=$1
fi

JENKINSURL=https://updates.jenkins.io/
BASEDIR=/home/klaas/Development/jenkins-update

LOCALURL=https://jenkins-update.ontwikkel.local/${VERSION}/stable
WORKDIR=${BASEDIR}/${VERSION}
DOWNLOADDIR=${BASEDIR}/${VERSION}/stable

# Location where jq can be found
# This file is downoadable from https://github.com/stedolan/jq
JQ=/home/klaas/Development/jenkins-update/jq

### functions ###

function download_file() {
  # download file
  curl -f -L "$1" --output "$2"  
  # Calculate hash
  CALCSHA256HASH=$( openssl dgst -binary -sha256 $2 | openssl base64 )
  # See if hashes match
  if [ "$3" == "${CALCSHA256HASH}" ];
  then
     echo "[ INFO  ] Download OK!" 
  else
     echo "[ ERROR ] Download $1 Failed!" 
     echo "[ ERROR ] Download $1 Failed!" >> ${WORKDIR}/${VERSION}-failed-downloads.txt
     
  fi
}


## Main ##

# Create downloaddir
mkdir -p ${DOWNLOADDIR}

# Create Work dir
mkdir -p ${WORKDIR}

# Download several files from Jenkins to a local copy
for FILE in latestCore.txt update-center.json update-center.actual.json update-center.json.html
do
  echo "[ INFO  ] Download ${FILE} from jenkins"
  curl -f "${JENKINSURL}/${VERSION}/${FILE}" --output "${WORKDIR}/${FILE}"
  echo $?
done

# Copy this update-center.json file to a local one
echo "[ INFO  ] Create copy of update-center.json to local-update-center.json"
cp "${WORKDIR}/update-center.json" "${WORKDIR}/local-update-center.json"

# Iterate though list to download the plugin file and modify it's location
for SECTION in ".core" ".plugins[]"
do
  # Iterate through relevant sections of the json file
  echo "[ INFO  ] ----- Analyzing section: ${SECTION}      -----" 

  ${JQ} "${SECTION}.name" ${WORKDIR}/update-center.actual.json | while read LINE
  do

    case ${SECTION} in
      ".plugins[]")
          PREFIX=".plugins"
          ;;
      ".core")
          PREFIX=""
          ;;
    esac

    NAME=$( ${JQ} -r "${PREFIX}.${LINE}.name" ${WORKDIR}/update-center.actual.json )
    URL=$( ${JQ} -r "${PREFIX}.${LINE}.url" ${WORKDIR}/update-center.actual.json )
    SHA256=$( ${JQ} -r "${PREFIX}.${LINE}.sha256" ${WORKDIR}/update-center.actual.json )
    PLUGINFILE="${URL##*/}"

    echo "[ INFO  ] Plugin           : ${NAME}"
    echo "[ INFO  ] Downloading file : ${URL}" 
    echo "[ INFO  ] To local copy    : ${DOWNLOADDIR}/${PLUGINFILE}" 

    # Download file to local storage
    download_file "${URL}" "${DOWNLOADDIR}/${PLUGINFILE}" "${SHA256}" 

    # Alter local-update-center.json file with local url
    echo "[ INFO  ] Altering the download URL for this file in local-update-center.json"
    sed -i "s|${URL}|${LOCALURL}/${PLUGINFILE}|g" ${WORKDIR}/local-update-center.json
  done
  echo "[ INFO  ] ----- Analyzing section: ${SECTION} Done -----"
done

