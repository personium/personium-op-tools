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

#
# MySQLスレーブ状態チェック
#
# 終了コード：
#   0: 正常終了
#   1: MySQLの接続に失敗
#   2: レプリケーションに失敗している。
#

. ${TOOL_DIR}/dc1-commons.sh
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# プロパティファイルからの読み込み
MYSQL_SLAVE_HOST=`getProp "com.fujitsu.dc.core.mysql.slave.host"`
MYSQL_SLAVE_PORT=`getProp "com.fujitsu.dc.core.mysql.slave.port"`
MYSQL_SLAVE_USER=`getProp "com.fujitsu.dc.core.mysql.backup.user.name"`
MYSQL_SLAVE_PASSWORD=`getProp "com.fujitsu.dc.core.mysql.backup.user.password"`

outputInfoLog "Checking slave DB status."

  STATUSES=`/usr/bin/mysql -u ${MYSQL_SLAVE_USER} --password=${MYSQL_SLAVE_PASSWORD} --host=${MYSQL_SLAVE_HOST} --port=${MYSQL_SLAVE_PORT} -e "SHOW SLAVE STATUS\G"`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to connect MySQL slave server. Host:${MYSQL_SLAVE_HOST} Port:${MYSQL_SLAVE_PORT} User:${MYSQL_SLAVE_USER}"
    exit 1
  fi

  STATUS=`echo "${STATUSES}" | /bin/egrep 'Slave_IO_Running|Slave_SQL_Running' | sed -s 's/ //g' | sed -s 's/^.*://g'`
  for stat in $STATUS
  do
    if [ "${stat}" != "Yes" ]; then
      outputErrorLog "Replication status is not reported as expected."
      echo "${STATUSES}"
    exit 2
    fi
  done

outputInfoLog "Replication status is reported as expected. Proceeding..."
exit 0

