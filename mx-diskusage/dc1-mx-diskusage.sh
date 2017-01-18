#!/bin/sh
#
# Personium
# Copyright 2016 FUJITSU LIMITED
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
ROOT_DIR=
DATE=`/bin/date +%Y%m%d`
MX_LOG=${ROOT_DIR}/fj/dc-mx/log/dc-mx-cron.log
MX_LOG_OLD=${MX_LOG}.`/bin/date +%Y%m%d -d '1 days ago'`



# 既存のログファイルを前日の日付を付加して退避する
## 前日の日付を付加したファイルが既に存在する場合は退避しない
## 退避に失敗した場合は、ログを出力し、処理を続行する
if [ ! -e ${MX_LOG_OLD} ]; then
  if [ -e ${MX_LOG} ]; then
    mv -f ${MX_LOG} ${MX_LOG_OLD} 2>&1
    if [ $? -ne 0 ]; then
      if [ ! -e ${MX_LOG_OLD} ]; then
        outputWarnLog "Dc-Mx cron log file rename failed."
      fi
    fi
  fi
fi

# /fj/dc-mx/dc-mx.propertiesの読み込み
CONF_PATH=/fj/dc-mx/dc-mx-cron.properties
. /fj/dc-mx/dc1-readPropertyFile.sh 

###########################################################################

## 実処理の開始 ##

## Curlの呼び出し URLはプロパティファイルから取得する。
MX_PROXY_BASE_URL=`getProp "com.fujitsu.dc.mx.proxy.baseUrl"`


outputInfoLog "Dc-MX cron started."
outputInfoLog "/usr/bin/curl -XGET ${MX_PROXY_BASE_URL}/__mx/stats"
/usr/bin/curl -XGET "${MX_PROXY_BASE_URL}/__mx/stats" -i -k -s >> ${MX_LOG} 2>&1
echo "" >> ${MX_LOG}
outputInfoLog "Dc-MX cron completed."
