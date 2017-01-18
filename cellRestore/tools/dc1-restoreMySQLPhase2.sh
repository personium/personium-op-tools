#!/bin/bash
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
# リストア元MySQLから指定されたCellのデータを抽出し、リストア先MySQLに登録する.
#
# 注意事項：
# - 作業用ディレクトリが既に存在する場合は、既存ディレクトリを削除後に再作成する.
#   作業用ディレクトリはツール実行後も削除しない。
#

_UNIT_USER_NAME=$1
_CELL_ID=$2

# プロパティファイルの読み込み
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh


_UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`

#
# リストア元MySQL情報
#

_SOURCE_MYSQL_HOST=`getProp "com.fujitsu.dc.core.mysql.restore.work.host"`
_SOURCE_MYSQL_PORT=`getProp "com.fujitsu.dc.core.mysql.restore.work.port"`
_SOURCE_MYSQL_USER=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.name"`
_SOURCE_MYSQL_PASSWORD=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.password"`
_SOURCE_MYSQL_DATABASE="${_UNIT_PREFIX}_${_UNIT_USER_NAME}"

#
# リストア先MySQL情報
#
_TARGET_MYSQL_HOST=`getProp "com.fujitsu.dc.core.mysql.master.host"`
_TARGET_MYSQL_PORT=`getProp "com.fujitsu.dc.core.mysql.master.port"`
_TARGET_MYSQL_USER=`getProp "com.fujitsu.dc.core.mysql.master.user.name"`
_TARGET_MYSQL_PASSWORD=`getProp "com.fujitsu.dc.core.mysql.master.user.password"`
_TARGET_MYSQL_DATABASE="${_UNIT_PREFIX}_${_UNIT_USER_NAME}"

#
# 共通設定
#

# リストア対象情報
_MYSQL_HOME="/usr/"

# ツール動作情報
_WORK_DIR="./restoreCellMySQL"
_TARGET_TABLE="CELL"
_MYSQL_OPTION="--host=${_SOURCE_MYSQL_HOST} --port=${_SOURCE_MYSQL_PORT} --user=${_SOURCE_MYSQL_USER} --password=${_SOURCE_MYSQL_PASSWORD} ${_SOURCE_MYSQL_DATABASE}"

#
# 指定されたテーブルの対象Cellに紐付くデータ抽出→登録を実行
#
function regist() {

  _TABLE_NAME=${1}
  
  # リストア対象のデータ総数を取得
  _TOTAL=`"${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} --skip-column-names -e "select count(*) from ${_TABLE_NAME} where id='${_CELL_ID}'" 2> ${_WORK_DIR}/error_message`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to read cell count from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi

  if [ ${_TOTAL} -eq 0 ]; then
    outputErrorLog "No cell data exists in restore DB. Cell ID: ${_CELL_ID}  Process aborted."
    exit 1
  fi

  # リストア対象のCellに紐付くデータを抽出
  "${_MYSQL_HOME}/bin/mysqldump" ${_MYSQL_OPTION} ${_TABLE_NAME} -w "id='${_CELL_ID}'" --skip-add-locks --skip-disable-keys --skip-add-drop-table --no-create-info > ${_WORK_DIR}/cell_restore_dump.sql 2> ${_WORK_DIR}/error_message
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to read cell data from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
  
  # リストア対象のMySQLへ抽出したデータを投入
  "${_MYSQL_HOME}/bin/mysql" --host=${_TARGET_MYSQL_HOST} --port=${_TARGET_MYSQL_PORT} --user=${_TARGET_MYSQL_USER} --password=${_TARGET_MYSQL_PASSWORD} ${_TARGET_MYSQL_DATABASE} < ${_WORK_DIR}/cell_restore_dump.sql 2> ${_WORK_DIR}/error_message
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to write cell data into master DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
}

#
# メイン処理
#
outputInfoLog "Starting cell data restoration into DB (Phase2).  Unit User: ${_UNIT_USER_NAME}  Cell Id: ${_CELL_ID}"

# ワークディレクトリ作成
# 既にワークディレクトリが存在する場合は事前に削除
if [ -e ${_WORK_DIR} ]; then
  outputInfoLog "Work directory already exists. Removing work directory. [${_WORK_DIR}]"
  rm -rf ${_WORK_DIR}
fi
/bin/mkdir -p ${_WORK_DIR}
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to create work directory. Process aborted."
  exit 1
fi

# テーブル毎にデータ抽出→登録を実行
regist "${_TARGET_TABLE}"

outputInfoLog "Cell data restoration into DB (Phase2) is completed. Proceeding..."

exit 0
