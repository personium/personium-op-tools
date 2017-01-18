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
_SKIP=$3

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
_MYSQL_HOME="/usr"

# ツール動作情報
_WORK_DIR="./restoreCellMySQL"
_TARGET_TABLES="ENTITY LINK DAV_NODE"
_SLEEP_TIME=1
_MYSQL_OPTION="--host=${_SOURCE_MYSQL_HOST} --port=${_SOURCE_MYSQL_PORT} --user=${_SOURCE_MYSQL_USER} --password=${_SOURCE_MYSQL_PASSWORD} ${_SOURCE_MYSQL_DATABASE}"

#
# 指定されたテーブルの対象Cellに紐付くデータ抽出→登録を実行
#
function regist() {
  
  _TABLE_NAME=${1}
  _TMP_TABLE_NAME="TMP_${_TABLE_NAME}"

  # リストア対象のデータ総数を取得
  _TOTAL=`"${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} --skip-column-names -e "select count(*) from ${_TMP_TABLE_NAME} where cell_id='${_CELL_ID}'" 2> ${_WORK_DIR}/error_message`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to read cell count from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
  outputInfoLog "Target data count in ${_TABLE_NAME} table: [$_TOTAL]"

  for (( i=0; i<${_TOTAL}; i=i+${_SKIP} ))
  do
  
    # リストア対象のCellに紐付くデータを抽出
    outputInfoLog "Read cell data from restore DB is started."
    "${_MYSQL_HOME}/bin/mysqldump" ${_MYSQL_OPTION} ${_TMP_TABLE_NAME} -w "cell_id='${_CELL_ID}' order by id limit ${i},${_SKIP}" --skip-add-locks --skip-disable-keys --skip-add-drop-table --no-create-info > ${_WORK_DIR}/cell_restore_dump.sql 2> ${_WORK_DIR}/error_message
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to read cell data from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
      exit 1
    fi
    sed -i -e 's/INSERT INTO `TMP_/INSERT INTO `/g' ${_WORK_DIR}/cell_restore_dump.sql

    # リストア対象のMySQLへ抽出したデータを投入
    outputInfoLog "Write cell data into master DB is started."
    "${_MYSQL_HOME}/bin/mysql" --host=${_TARGET_MYSQL_HOST} --port=${_TARGET_MYSQL_PORT} --user=${_TARGET_MYSQL_USER} --password=${_TARGET_MYSQL_PASSWORD} ${_TARGET_MYSQL_DATABASE} < ${_WORK_DIR}/cell_restore_dump.sql 2> ${_WORK_DIR}/error_message
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to write cell data into master DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
      exit 1
    fi

    _PROCESSED_COUNT=`expr ${i} + ${_SKIP}`
    if [ ${_PROCESSED_COUNT} -gt ${_TOTAL} ]; then
      _PROCESSED_COUNT=${_TOTAL}
    fi
    outputInfoLog "${_TABLE_NAME} table: [${_PROCESSED_COUNT}/${_TOTAL}]"

    # sleep...
    sleep ${_SLEEP_TIME}
  done
}

# テンポラリテーブルの作成
function create_tmp_table() {
  outputInfoLog "Create temporary table."
  "${_MYSQL_HOME}/bin/mysqldump" ${_MYSQL_OPTION} --no-data --skip-add-locks --skip-disable-keys --skip-add-drop-table > ${_WORK_DIR}/create_tmp_table.sql 2> ${_WORK_DIR}/error_message
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to create temporary table. create_tmp_table.sql (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
  sed -i -e 's/CREATE TABLE `/CREATE TABLE `TMP_/g' ${_WORK_DIR}/create_tmp_table.sql

  "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} < ${_WORK_DIR}/create_tmp_table.sql 2> ${_WORK_DIR}/error_message
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to create temporary table. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
}

# テンポラリテーブルにデータを投入
function insert_tmp_table_from_work() {
  # テーブル毎にデータ抽出→登録を実行
  for _TARGET_TABLE in ${_TARGET_TABLES}
  do
    _TMP_TABLE_NAME="TMP_${_TARGET_TABLE}"
    outputInfoLog "Insert restore data into temporary table from work table ${_TARGET_TABLE} ."
    "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} -e "INSERT INTO ${_TMP_TABLE_NAME} SELECT * FROM ${_TARGET_TABLE} WHERE cell_id='${_CELL_ID}'" 2> ${_WORK_DIR}/error_message
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to insert restore data into temporary table. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
      exit 1
    fi
  done
}

#
# メイン処理
#
outputInfoLog "Starting cell data restoration into DB (Phase1).  Unit User: ${_UNIT_USER_NAME}  Cell Id: ${_CELL_ID}"

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

# テンポラリテーブルの作成
create_tmp_table

# テンポラリテーブルにデータを投入
insert_tmp_table_from_work


# テーブル毎にデータ抽出→登録を実行
for _TARGET_TABLE in ${_TARGET_TABLES}
do
  regist "${_TARGET_TABLE}"
done

outputInfoLog "Cell data restoration into DB (Phase1) is completed. Proceeding..."

exit 0

