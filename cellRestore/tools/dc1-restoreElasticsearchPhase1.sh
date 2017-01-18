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
# リストア元MySQLから指定されたCellのデータを抽出し、リストア先Elasticsearchに登録する.
# リストアに使用するデータはリストア対象のセルのデータのみを抽出したテンポラリテーブルのデータを使用する.
# なお、テンポラリテーブルへのデータ投入はdc1-restoreMySQLPhase1にて実施している.
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
# リストア先Elasticsearch情報
#
_TARGET_ES_HOST=`getProp "com.fujitsu.dc.core.es.master.host"`
_TARGET_ES_INDEX="${_UNIT_PREFIX}_${_UNIT_USER_NAME}"

#
# 共通設定
#

# リストア対象情報
_MYSQL_HOME="/usr/"

# ツール動作情報
_WORK_DIR="./restoreCellES"
_TARGET_TABLES="ENTITY LINK DAV_NODE"
_SLEEP_TIME=1
_MYSQL_OPTION="--host=${_SOURCE_MYSQL_HOST} --port=${_SOURCE_MYSQL_PORT} --user=${_SOURCE_MYSQL_USER} --password=${_SOURCE_MYSQL_PASSWORD} ${_SOURCE_MYSQL_DATABASE} --skip-column-names"

#
# 指定されたテーブルの対象Cellに紐付くデータ抽出→登録を実行
#
function regist() {
  
  _TABLE_NAME=${1}
  _TMP_TABLE_NAME="TMP_${_TABLE_NAME}"
  
  # リストア対象のデータ総数を取得
  _TOTAL=`"${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} -e "select count(*) from ${_TMP_TABLE_NAME} where cell_id='${_CELL_ID}'" 2> ${_WORK_DIR}/error_message`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to read cell count from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
    exit 1
  fi
  outputInfoLog "Target data count in ${_TABLE_NAME} table: [$_TOTAL]"

  for (( i=0; i<${_TOTAL}; i=i+${_SKIP} ))
  do
  
    # リストア対象のCellに紐付くデータを抽出
    if [ "DAV_NODE" = "${_TABLE_NAME}" ]; then
      # DAV_NODE
      "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} -e "select CONCAT('{\"create\":{\"_index\":\"${_TARGET_ES_INDEX}\", \"_type\":\"dav\", \"_id\":\"', id, '\", \"_routing\":\"', cell_id, '\"}}', CHAR(10), '{\"c\":\"', cell_id, '\",\"b\":', IFNULL(CONCAT('\"', box_id, '\"'), 'null'), ',\"t\":', IFNULL(CONCAT('\"', node_type, '\"'), 'null'), ',\"s\":', IFNULL(CONCAT('\"', parent_id, '\"'), 'null'),',\"a\":', IFNULL(acl, 'null'), ',\"f\":', IFNULL(file, 'null'), ',\"d\":', IFNULL(properties, 'null'), ',\"o\":', IFNULL(children, 'null'), ',\"u\":', IFNULL(updated, 'null'), ',\"p\":', IFNULL(published, 'null'), '}') from ${_TMP_TABLE_NAME} where cell_id='${_CELL_ID}' order by id limit ${i},${_SKIP}" > ${_WORK_DIR}/cell_mysql_source.txt 2> ${_WORK_DIR}/error_message
      if [ $? -ne 0 ]; then
        outputErrorLog "Failed to read cell data from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
        exit 1
      fi

    elif [ "LINK" = "${_TABLE_NAME}" ]; then
      # LINK
      "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} -e "select CONCAT('{\"create\":{\"_index\":\"${_TARGET_ES_INDEX}\", \"_type\":\"link\", \"_id\":\"', id, '\", \"_routing\":\"', cell_id, '\"}}', CHAR(10), '{\"c\":\"', cell_id, '\",\"b\":', IFNULL(CONCAT('\"', box_id, '\"'), 'null'), ',\"n\":', IFNULL(CONCAT('\"', node_id, '\"'), 'null'), ',\"t1\":', IFNULL(CONCAT('\"', ent1_type, '\"'), 'null'), ',\"t2\":', IFNULL(CONCAT('\"', ent2_type, '\"'), 'null'), ',\"k1\":', IFNULL(CONCAT('\"', ent1_id, '\"'), 'null'), ',\"k2\":', IFNULL(CONCAT('\"', ent2_id, '\"'), 'null'), ',\"u\":', IFNULL(updated, 'null'), ',\"p\":', IFNULL(published, 'null'), '}') from ${_TMP_TABLE_NAME} where cell_id='${_CELL_ID}' order by id limit ${i},${_SKIP}" > ${_WORK_DIR}/cell_mysql_source.txt 2> ${_WORK_DIR}/error_message
      if [ $? -ne 0 ]; then
        outputErrorLog "Failed to read cell data from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
        exit 1
      fi

    else
      # ENTITY
      "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} -e "select CONCAT('{\"create\":{\"_index\":\"${_TARGET_ES_INDEX}\", \"_type\":\"', type, '\", \"_id\":\"', id, '\", \"_routing\":\"', cell_id, '\"}}', CHAR(10), '{\"c\":\"', cell_id, '\",\"b\":', IFNULL(CONCAT('\"', box_id, '\"'), 'null'), ',\"n\":', IFNULL(CONCAT('\"', node_id, '\"'), 'null'), ',\"t\":', IFNULL(CONCAT('\"', entity_id, '\"'), 'null'), ',\"s\":', IFNULL(declared_properties, 'null'), ',\"d\":', IFNULL(dynamic_properties, 'null'), ',\"h\":', IFNULL(hidden_properties, 'null'), ',\"l\":', IFNULL(links, 'null'), ',\"u\":', IFNULL(updated, 'null'), ',\"p\":', IFNULL(published, 'null'), '}') from ${_TMP_TABLE_NAME} where cell_id='${_CELL_ID}' order by id limit ${i},${_SKIP}" > ${_WORK_DIR}/cell_mysql_source.txt 2> ${_WORK_DIR}/error_message
      if [ $? -ne 0 ]; then
        outputErrorLog "Failed to read cell data from restore DB. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
        exit 1
      fi

    fi

    # リストア対象のElasticsearchへ抽出したデータを投入
    cat ${_WORK_DIR}/cell_mysql_source.txt | sed -e 's/[}]\\n[{]/\}\n\{/g' > ${_WORK_DIR}/cell_restore_source.txt
    sed -i -e 's/\\\\/\\/g' ${_WORK_DIR}/cell_restore_source.txt
    /usr/bin/curl -XPOST "http://${_TARGET_ES_HOST}/_bulk" --data-binary @${_WORK_DIR}/cell_restore_source.txt > ${_WORK_DIR}/cell_restore_response.txt 2> ${_WORK_DIR}/error_message
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to write cell data into Elasticsesarch. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
      exit 1
    fi

    _RESULT_JSON=`cat ${_WORK_DIR}/cell_restore_response.txt | python -mjson.tool`
    if [ 0 -ne $? ]; then
      # curlから返却された結果が、JSONでない場合、エラーとする。
      outputErrorLog "Failed to write cell data into Elasticsesarch. (See [${_WORK_DIR}/cell_restore_response.txt].) Process aborted."
      exit 1
    fi

    _ERROR_COUNT=`echo ${_RESULT_JSON} | grep "\"error\":" | wc -l`
    if [ 0 -ne ${_ERROR_COUNT} ]; then
      # curlから返却されたJSONに、「"error":」が含まれている場合、エラーとする。 
      outputErrorLog "Failed to write cell data into Elasticsesarch. (See [${_WORK_DIR}/cell_restore_response.txt].) Process aborted."
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

#
# メイン処理
#
outputInfoLog "Starting cell data restoration into Elasticsearch (Phase1).  Unit User: ${_UNIT_USER_NAME}  Cell ID: ${_CELL_ID}"

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
for _TARGET_TABLE in ${_TARGET_TABLES}
do
  regist "${_TARGET_TABLE}"
done

# Elasticsearch index refresh
/usr/bin/curl -XPOST "http://${_TARGET_ES_HOST}/${_TARGET_ES_INDEX}/_refresh" -s > ${_WORK_DIR}/cell_restore_response.txt 2> ${_WORK_DIR}/error_message
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to refresh Elasticsesarch. (Cause: `cat ${_WORK_DIR}/error_message`) Process aborted."
  exit 1
fi

_RESULT_JSON=`cat ${_WORK_DIR}/cell_restore_response.txt | python -mjson.tool`
if [ 0 -ne $? ]; then
  # curlから返却された結果が、JSONでない場合、エラーとする。
  outputErrorLog "Failed to refresh Elasticsesarch. (See [${_WORK_DIR}/cell_restore_response.txt].) Process aborted."
  exit 1
fi

_ERROR_COUNT=`echo ${_RESULT_JSON} | grep "\"error\":" | wc -l`
if [ 0 -ne ${_ERROR_COUNT} ]; then
  # curlから返却されたJSONに、「"error":」が含まれている場合、エラーとする。 
  outputErrorLog "Failed to refresh Elasticsesarch. (See [${_WORK_DIR}/cell_restore_response.txt].) Process aborted."
  exit 1
fi

outputInfoLog "Cell data restoration on Elasticsearch (Phase1) is completed. Proceeding..."

exit 0
