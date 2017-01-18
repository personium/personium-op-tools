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
# リストア用のMySQLワークインスタンスを停止する
#
# 終了コード：
#   0: 正常終了
#   1: 起動していない
#   2: 停止失敗
#

. ${TOOL_DIR}/dc1-commons.sh
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# プロパティファイルからの読み込み
MYSQL_DATA_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.mysql.dir"`
PID_FILE=$MYSQL_DATA_DIR/mysql_restore.pid

outputInfoLog "Stopping restore DB."

if [ -s "${PID_FILE}" ]; then
  PID=`cat "${PID_FILE}"`
  if (kill -0 ${PID} 2>/dev/null); then
    kill ${PID}

    if [ ${?} -ne 0 ]; then
       # プロセスは存在するものの、プロセスの停止に失敗した状態。
       outputWarnLog "Failed to stop restore DB. Please kill the MySQL process manually after the whole script is completed."
       exit 1
    fi

    /bin/rm "${PID_FILE}"
    outputInfoLog "Stopping restore DB is completed."
    exit 0
  fi
fi

outputWarnLog "Could not find process of restore DB. Restore DB might be stopped already."
exit 1

