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
# リストア用のMySQLワークインスタンスにコピーしたデータディレクトリを削除する
#
# 引数：
# ・ユニットユーザ名
# ・リストア対象バックアップデータの日付(YYYYMMDD)
#
# 終了コード：
#   0: 正常終了
#   1: 引数エラー
#

. ${TOOL_DIR}/dc1-commons.sh

function removeFile() {
  REMOVE_TARGET=$1
  if [ -e "${REMOVE_TARGET}" ]; then
    /bin/rm -r "${REMOVE_TARGET}"
    if [ $? -ne 0 ]; then
      outputWarnLog "Failed to remove work files for cell restore. Proceeding..."
    fi
  fi
}

# 引数チェック
if [ $# -ne 2 ]; then
  outputErrorLog "Usage: dc1-disposeGarbage.sh <unituser-name> <restore-target-date>"
  exit 1
fi

UNIT_USER=$1
BACKUP_DATE=$2

. ${TOOL_DIR}/dc1-readPropertyFile.sh

# プロパティファイルからの読み込み
UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`
MYSQL_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.mysql.dir"`
WEBDAV_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.webdav.dir"`
WEBDAV_BACKUP_PREFIX=`getProp "com.fujitsu.dc.core.backup.dav.prefix"`
EVENTLOG_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.eventlog.dir"`
EVENTLOG_BACKUP_PREFIX=`getProp "com.fujitsu.dc.core.backup.eventlog.prefix"`

outputInfoLog "Removing work files for cell restore. Proceeding..."

# MySQL
###  入力パラメタ ${UNIT_USER} は 記号変換していない。(e.g '-' => @002 ) このため変換が必要
RAW_MYSQL_UNITUSER_NAME=`convertUnitUserDBtoRawMySQLName ${UNIT_USER}`
removeFile ${MYSQL_RESTORE_BASE_DIR}/${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME}

# WebDAV
removeFile ${WEBDAV_RESTORE_BASE_DIR}/${UNIT_USER}

# EventLog
removeFile ${EVENTLOG_RESTORE_BASE_DIR}/${UNIT_USER}

outputInfoLog "Removing work files for cell restore is completed. Proceeding..."

exit 0
