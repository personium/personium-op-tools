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
# Cell単位の整合性を確認する
#
# ・不整合があった場合は、${RESULT_FILE_PATH}に結果を出力する。
# ・作業ディレクトリが存在しない場合は作成。
#   すでに存在する場合、ディレクトリ配下の${RESULT_FILE_PATH}、作業ファイルはクリアする。
#
# 引数：
# ・$1 UnitUser名（必須）
# ・$2 CellのID（必須）
# ・$3 作業ディレクトリ（オプション）
#
# 復帰コード：
# ・0 正常終了
# ・1 異常終了
# ・2 不整合を検出
# ・3 パラメータ異常
#
# 不整合検出時の例：
# ・MySQL側にデータが無く、Elasticsearchにある（MySQLMiss）
#   > "u":1394595138928,"_id":"F8RXW9qRTZupbC7-ge-1pB","_type":"UserData"
# ・MySQL側にデータが有り、Elasticsearchに無い（EsMiss）
#   < "u":1394595138928,"_id":"F8RXW9qRTZupbC7-ge-1pB","_type":"UserData"
# ・MySQL側、Elasticsearchにデータが有り、updatedが異なる（TimestampMissMatch）
#   > "u":1394595138935,"_id":"F8RXW9qRTZupbC7-ge-1pB","_type":"UserData"
#   < "u":1394595138928,"_id":"F8RXW9qRTZupbC7-ge-1pB","_type":"UserData"
# ・MySQL側にデータが有り、Davファイルの実体が無い（DavFsMiss）
#   DavFsMiss dav_id:[F8RXW9qRTZupbC7-ge-1pB], file_path:[/fjnfs/dc-core/dav/vet/F8/RX/F8RXW9qRTZupbC7-ge-1pB]
#
# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

# 引数チェック
if [ $# -lt 2 ]; then
  outputErrorLog "Usage: dc1-invokeDiffValidation.sh <unituser-name> <cell-id> <work-dir>"
  exit 3
fi

UNIT_USER=$1
CELL_ID=$2
WORK_DIR=$3
if [ -z ${WORK_DIR} ]; then
  WORK_DIR="${TOOL_DIR}/diff"
fi

# プロパティファイル読込
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# 利用するプロパティ
PROP_ES_MASTER_HOST="com.fujitsu.dc.core.es.master.host"
PROP_UNIT_PREFIX="com.fujitsu.dc.core.es.unitPrefix"
PROP_MY_SQL_HOST="com.fujitsu.dc.core.mysql.slave.host"
PROP_MY_SQL_PORT="com.fujitsu.dc.core.mysql.slave.port"
PROP_MY_SQL_USER="com.fujitsu.dc.core.mysql.backup.user.name"
PROP_MY_SQL_PASSWORD="com.fujitsu.dc.core.mysql.backup.user.password"
PROP_DAV_PATH="com.fujitsu.dc.core.webdav.basedir"

# プロパティファイル中の必須プロパティ存在チェック
mandatoryPropKeys=( ${PROP_ES_MASTER_HOST} ${PROP_UNIT_PREFIX} ${PROP_MY_SQL_HOST} ${PROP_MY_SQL_PORT} ${PROP_MY_SQL_USER} ${PROP_MY_SQL_PASSWORD} ${PROP_DAV_PATH} )
checkMandatoryProperties ${mandatoryPropKeys[@]}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
#   エラーログは出力済
    exit 1
fi

# プロパティ値取得
ES_MASTER_HOST=`getProp ${PROP_ES_MASTER_HOST}`
UNIT_PREFIX=`getProp ${PROP_UNIT_PREFIX}`
MY_SQL_HOST=`getProp ${PROP_MY_SQL_HOST}`
MY_SQL_PORT=`getProp ${PROP_MY_SQL_PORT}`
MY_SQL_USER=`getProp ${PROP_MY_SQL_USER}`
MY_SQL_PASSWORD=`getProp ${PROP_MY_SQL_PASSWORD}`
DAV_PATH=`getProp ${PROP_DAV_PATH}`

DATABASE="${UNIT_PREFIX}_${UNIT_USER}"
MYSQL_OPTION="--host=${MY_SQL_HOST} --port=${MY_SQL_PORT} --user=${MY_SQL_USER} --password=${MY_SQL_PASSWORD}"

#
# メイン
#

# 処理開始時メッセージを出力する。
outputInfoLog "Start cell data validation.  UnitUser: ${UNIT_USER}"

RESULT_FILE_PATH="${WORK_DIR}/diff_result.txt"

# ワークディレクトリ作成
/bin/mkdir -p ${WORK_DIR}
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to create work directory [${WORK_DIR}]. Process aborted."
  exit 1
fi

# 整合性チェック結果出力ファイルの初期化
rm -f ${WORK_DIR}/{my_id_cell.txt,my_id_link.txt,my_id_entity.txt,my_id_dav.txt,my.txt,es.txt,error_message}
rm -f ${RESULT_FILE_PATH}

#
# Elasticsearchからデータ抽出
#
outputInfoLog "Extracting cell data from Elasticsearch."

# Cell以外
python ${TOOL_DIR}/dc1-searchCellDataListFromElasticsearch.py ${ES_MASTER_HOST} ${UNIT_PREFIX} ${UNIT_USER} ${CELL_ID} "${WORK_DIR}/es.txt"
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

# Cell
CELL_DATA=`curl -s -XGET "http://${ES_MASTER_HOST}/${UNIT_PREFIX}_ad/Cell/${CELL_ID}?routing=pcsCell" 2> ${WORK_DIR}/error_message`
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from Elasticsearch. Cause: `cat ${WORK_DIR}/error_message`"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi
echo ${CELL_DATA} | python -c 'import sys,json;data=json.loads(sys.stdin.read()); print "\"u\":%d,\"_id\":\"%s\",\"_type\":\"Cell\"" % (data["_source"]["u"], data["_id"])' >> "${WORK_DIR}/es.txt" 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from Elasticsearch. Cause: `cat ${WORK_DIR}/error_message` , Cell get response:「${CELL_DATA}」"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

# MySQLからデータ抽出
outputInfoLog "Extracting cell data from MySQL(CELL)."

mysql ${MYSQL_OPTION} ${DATABASE} --skip-column -e "select concat('\"u\":',updated,',\"_id\":\"',id,'\",\"_type\":\"',type,'\"') from CELL where id='${CELL_ID}'" > "${WORK_DIR}/my_id_cell.txt" 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from MySQL(CELL). Cause: `cat ${WORK_DIR}/error_message`"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

outputInfoLog "Extracting cell data from MySQL(ENTITY)."

mysql ${MYSQL_OPTION} ${DATABASE} --skip-column -e "select concat('\"u\":',updated,',\"_id\":\"',id,'\",\"_type\":\"',type,'\"') from ENTITY where cell_id='${CELL_ID}'" > "${WORK_DIR}/my_id_entity.txt" 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from MySQL(ENTITY). Cause: `cat ${WORK_DIR}/error_message`"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

outputInfoLog "Extracting cell data from MySQL(LINK)."

mysql ${MYSQL_OPTION} ${DATABASE} --skip-column -e "select concat('\"u\":',updated,',\"_id\":\"',id,'\",\"_type\":\"link\"') from LINK where cell_id='${CELL_ID}'" > "${WORK_DIR}/my_id_link.txt" 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from MySQL(LINK). Cause: `cat ${WORK_DIR}/error_message`"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

outputInfoLog "Extracting cell data from MySQL(DAV_NODE)."

mysql ${MYSQL_OPTION} ${DATABASE} --skip-column -e "select concat('\"u\":',updated,',\"_id\":\"',id,'\",\"_type\":\"dav\"') from DAV_NODE where cell_id='${CELL_ID}'" > "${WORK_DIR}/my_id_dav.txt" 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search from MySQL(DAV_NODE). Cause: `cat ${WORK_DIR}/error_message`"
  outputErrorLog "Cell data validation is failed. Process aborted."
  exit 1
fi

# ここからはデータ抽出が完了しているので、エラーが発生した場合も比較処理を続行する

# 不整合確認（MySQL - Elasticsearch）
outputInfoLog "Performing validation between MySQL and Elasticsearch."

cat "${WORK_DIR}/"{my_id_cell.txt,my_id_entity.txt,my_id_link.txt,my_id_dav.txt} | sort > "${WORK_DIR}/my.txt"
if [ ! -s "${WORK_DIR}/my.txt" ]; then
  # MySQL側に１件も対象データが存在しない場合はエラーを出力
  outputErrorLog "No data associated with cell_id:[${CELL_ID}] was found in slave database."
  echo "No data associated with cell_id:[${CELL_ID}] was found in slave database." >> "${RESULT_FILE_PATH}"
fi
sort "${WORK_DIR}/es.txt" | diff "${WORK_DIR}/my.txt" - >> "${RESULT_FILE_PATH}"

# 不整合確認（MySQL - Dav）
outputInfoLog "Performing validation between MySQL and Dav."

MY_DAV_NODES=`mysql ${MYSQL_OPTION} ${DATABASE} --skip-column -e "select id from DAV_NODE where cell_id='${CELL_ID}' and node_type='dav.file'"` 2> ${WORK_DIR}/error_message
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  outputErrorLog "Failed to search dav data from MySQL. Cause: `cat ${WORK_DIR}/error_message`"
fi

for MY_DAV_NODE in ${MY_DAV_NODES}
do
  SUB_DIR=`echo ${MY_DAV_NODE} | sed -e 's/^\(..\)\(..\)\(.*\)$/\1\/\2/'`
  DAV_FILE_PATH="${DAV_PATH}/${UNIT_USER}/${SUB_DIR}/${MY_DAV_NODE}"
  if [ ! -f "${DAV_FILE_PATH}" ]; then
    echo "DavFsMiss dav_id:[${MY_DAV_NODE}], file_path:[${DAV_FILE_PATH}]" >> "${RESULT_FILE_PATH}"
  fi
done


# 処理成功のログを出力する。
if [ ! -s ${RESULT_FILE_PATH} ]; then
  
  # 作業用ファイル削除
  rm -f ${WORK_DIR}/{my_id_cell.txt,my_id_link.txt,my_id_entity.txt,my_id_dav.txt,my.txt,es.txt}
  
  outputInfoLog "Cell data validation is successfully completed."
  exit 0

else
  outputWarnLog "Cell data validation reported some inconsistency. See [${RESULT_FILE_PATH}]."
  exit 2
fi

