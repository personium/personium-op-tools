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
# リストア用のMySQLワークインスタンスを起動する
#
# 終了コード：
#   0: 正常終了
#   1: 既に起動している
#   2: 起動失敗
#

function waitFor() {
  PID_PATH="$1"
  TIMEOUT=60
  i=0

  while test $i -ne ${TIMEOUT} ; do
    # wait for a PID-file to pop into existence.
    test -s "${PID_PATH}" && i='' && break
    i=`expr $i + 1`
    sleep 1
  done

  if test -z "$i" ; then
    return 0
  else
    return 1
  fi
}


. ${TOOL_DIR}/dc1-commons.sh
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# プロパティファイルからの読み込み
MYSQL_DATA_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.mysql.dir"`

outputInfoLog "Starting restore DB."


MY_CNF=/etc/my_restore.cnf
PID_FILE=${MYSQL_DATA_DIR}/mysql_restore.pid

if [ -s "${PID_FILE}" ]; then
  PID=`cat "${PID_FILE}"`
  if (kill -0 ${PID} 2>/dev/null); then
     outputInfoLog "Restore DB is already running. Proceeding..."
     exit 0
  fi
fi

/usr/bin/mysqld_safe --defaults-file=${MY_CNF} --datadir="${MYSQL_DATA_DIR}" --pid-file="${PID_FILE}" >/dev/null 2>&1 &
waitFor "${PID_FILE}"
if [ ${?} -ne 0 ]; then
  outputErrorLog "Failed to start restore DB. Process aborted."
  exit 2
fi

outputInfoLog "Restore DB is started. Proceeding..."
exit 0

