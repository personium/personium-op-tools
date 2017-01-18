#!/bin/sh
#
# personium
# Copyright 2014 FUJITSU LIMITED
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Restore personium.io data from ADS to Elasticsearch.
#
# Arguments
#  -p {path}     : path name of properties file (required)
#  -c            : clear index of Elasticsearch (optional)
#  -i {name}     : name of restore index on Elasticsearch (optional)
#  -r {replicas} : number of replicas (optional)
#

#----------------------------------------------
# Environment variables.
#
JAVA_HOME=/opt/jdk
PATH=${JAVA_HOME}/bin:${PATH}
ES_PORT=9200
SCRIPT_LOG=/fj/dc-recovery/log/dc-recovery.log.`/bin/date +%Y%m%d`
/bin/mkdir -p /fj/dc-recovery/log

## INFO log output.
## arguments:
##   $1: output message
function log_info() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [INFO ] $1" >> ${SCRIPT_LOG}
}

## WARN log output.
## arguments:
##   $1: output message
function log_warn() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [WARN ] $1" >> ${SCRIPT_LOG}
}

## ERROR log output.
## arguments:
##   $1: output message
function log_error() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [ERROR] $1" >> ${SCRIPT_LOG}
}


## read property
## arguments:
##   $1: property name
##   $2: property file path
function read_property() {
  local value=`/bin/grep "${1}" ${2} | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 -o -z "${value}" ]; then
    log_error "unknown property name: ${1}"
    exit 1
  fi
  echo ${value}
}

## read properties file.
## arguments:
##   $1: properties file path
##
function read_properties() {
  local value=`read_property com.fujitsu.dc.core.es.hosts ${1}`
  if [[ "${value}" =~ "," ]]; then
    ES_HOST=`echo ${value} | tr ',|:' ' ' | awk '{print $1}'`
  else
    ES_HOST=`echo ${value} | tr ':' ' ' | awk '{print $1}'`
  fi
}


## Main process.
##

# Analysis arguments.
IS_CLEAR=
RESTORE_INDEX=
while getopts ":p:ci:r:" ARGS
do
  case $ARGS in
  p )
    PROPERTIES_FILE_PATH=${OPTARG}
    ;;
  c )
    IS_CLEAR="-c"
    ;;
  i )
    RESTORE_INDEX=${OPTARG}
    ;;
  r )
    NUMBER_OF_REPLICAS=${OPTARG}
    ;;
  :)
    log_warn "[-$OPTARG] requires an argument."
    exit 1
    ;;
  esac
done


# -p option check.
# Property file path.
#
if [ -z "${PROPERTIES_FILE_PATH}" -o ! -f ${PROPERTIES_FILE_PATH} ]; then
  log_warn "[-p] arguments is necessary, or invalid file path."
  exit 1
fi


# -i option check.
# Restore target index name.
#
if [ -z "${PROPERTIES_FILE_PATH}" -o ! -f ${PROPERTIES_FILE_PATH} ]; then
  log_warn "[-p] arguments is necessary, or invalid file path."
  exit 1
fi

# Read properties.
#
read_properties ${PROPERTIES_FILE_PATH}


# Retrieve version of Elasticsearch.
#
ES_VERSION=`curl -X GET "http://${ES_HOST}:${ES_PORT}/" -s | python -c 'import sys,json;data=json.loads(sys.stdin.read()); print data["version"]["number"]' 2> ${SCRIPT_LOG}`
if [ $? -ne 0 -o -z "${ES_VERSION}" ]; then
  log_error "Failed to connect Elasticsearch (host=${ES_ESHOT}, detail=${ES_VERSION})."
  exit 1
fi

# Retrive number of replicas from Elasticsearch.
#
REPLICAS_OF_INDICES=`python /fj/dc-recovery/retrieveNumberOfReplica.py ${ES_HOST} ${ES_PORT} ${ES_VERSION} 2> ${SCRIPT_LOG}`
if [ $? -ne 0 ]; then
  log_error "Failed to retrieve number_of_replica from Elasticsearch (host=${ES_HOST}, detail=${REPLICAS_OF_INDICES})."
  exit
fi
# set to array.
REPLICAS=()
for indices in ${REPLICAS_OF_INDICES}
do
   REPLICAS=(${REPLICAS[@]} ${indices})
done

# Fix to number_of_replica for restore.
#
if [ -n "${RESTORE_INDEX}" ]; then
  replicas=
  for indices in ${REPLICAS[@]}
  do
    index=( `echo ${indices} | tr ':' '\t'` )
    replicas=${index[1]}
    if [ "${RESTORE_INDEX}" == "${index[0]}" ]; then
      break
    fi
  done
  if [ -z ${replicas} ]; then
    log_info "Elasticsearch cluster is empty."
  else
    NUMBER_OF_REPLICAS=${replicas}
  fi
else
  first_index=${REPLICAS[0]}
  replicas=( `echo ${first_index} | tr ':' '\t'` )
  if [ -n "${replicas[1]}" ];then
    NUMBER_OF_REPLICAS=${replicas[1]}
  fi
fi
if [ -z "${NUMBER_OF_REPLICAS}" ]; then
  log_error "Failed to setup of number_of_replica."
  exit 1
fi


# Call to Elasticsearch index restore tool.
#
i_opt=
if [ -n "${RESTORE_INDEX}" ]; then
  i_opt="-i ${RESTORE_INDEX}"
fi
java -Xmx1024m -jar /fj/dc-recovery/dc1-recovery.jar -p ${PROPERTIES_FILE_PATH} ${IS_CLEAR} -i ${RESTORE_INDEX} -r ${NUMBER_OF_REPLICAS} | tee -a ${SCRIPT_LOG}
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  log_info "Elasticsearch restore is failed."
  exit 1
fi
log_info "Elasticsearch restore is successful."


exit 0
