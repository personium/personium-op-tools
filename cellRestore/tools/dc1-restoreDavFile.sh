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

# MySQLから指定されたCellのWebDavファイルのIDを抽出し、リストアする.
# リストアに使用するデータはリストア対象のセルのデータのみを抽出したテンポラリテーブルのデータを使用する.
# なお、テンポラリテーブルへのデータ投入はdc1-restoreMySQLPhase1にて実施している.

# プロパティファイル読込
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh


# オプション設定
#    $1:ユニットユーザ名 (必須）
#    $2:CellID　(必須）
#    $3:リストア対象日付　(必須）
#    $4:1ループあたりの処理件数　デフォルト 10
#    $5:ループ時の休眠時間(秒) デフォルト 1秒
UNIT_USER_NAME=$1
CELL_ID=$2
RESTORE_DATE=$3
LIMIT_COUNT=$4
_SLEEP_PERIOD_IN_SEC=$5

# パラメタ数チェック。 LIMIT_COUNT, _SLEEP_PERIOD_IN_SEC はオプション
if [ $# -lt 3 ]; then
   outputErrorLog "Required parameter is missing. Process aborted."
   exit 1
fi

if [ -z ${LIMIT_COUNT} ]; then
   LIMIT_COUNT=10
fi

if [ -z ${_SLEEP_PERIOD_IN_SEC} ]; then
   _SLEEP_PERIOD_IN_SEC=1
fi


# プロパティファイルの読み込み
UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`

MYSQL_WORK_HOST=`getProp "com.fujitsu.dc.core.mysql.restore.work.host"`
MYSQL_WORK_PORT=`getProp "com.fujitsu.dc.core.mysql.restore.work.port"`
MYSQL_USER=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.name"`
MYSQL_PASSWORD=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.password"`

DAV_RESTORE_TARGET_DIR=`getProp "com.fujitsu.dc.core.webdav.basedir"`
DAV_WORK_SPACE=`getProp "com.fujitsu.dc.core.restore.workspace.webdav.dir"`
DAV_BKUP_FILE_PREFIX=`getProp "com.fujitsu.dc.core.backup.dav.prefix"`

# インデックス名
INDEX_NAME=${UNIT_PREFIX}_${UNIT_USER_NAME}


# Davファイル関連
RESTORE_ID_LIST="/tmp/restore_dav_id_list"
RESTORE_FILE_PATH_LIST="/tmp/restore_dav_file_path_list"
RESTORE_ERROR_MESSAGE="/tmp/restore_dav_error_message"



# ワークテーブルからDavIDを取得する
function read_david_from_work_table() {
  # 読み込んだプロパティファイルからmysqlコマンドを生成
  ${MYSQL_CMD} ${INDEX_NAME} --skip-column-names -e "select id from TMP_DAV_NODE where cell_id='${CELL_ID}' and node_type='dav.file' limit $1,$2;" > ${RESTORE_ID_LIST}
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to read cell data from restore DB [${INDEX_NAME}]. (failed MySQL command : select id from TMP_DAV_NODE where cell_id='${CELL_ID}' and node_type='dav.file' limit $1,$2;) Process aborted."
    exit 1
  fi
}

# DavファイルIDを XX/YY/XXYYZZZZZZZZ に変換する
function transformation_webdav_id() {
  SUB_DIR=`echo $1 | sed -e 's/^\(..\)\(..\)\(.*\)$/\1\/\2/'`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to transformation WebDav ID($1). Process aborted."
    exit 1
  fi

  echo "${UNIT_USER_NAME}/${SUB_DIR}/$1" >> ${RESTORE_FILE_PATH_LIST}
}

# あらかじめ抽出したDAVファイルをリストアする
function restore_webdav() {
  if [ ! -d ${DAV_RESTORE_TARGET_DIR} ];then
    outputErrorLog "Webdav restore directory is not found. [${DAV_RESTORE_TARGET_DIR}]"
    exit 1
  fi

  for RESTORE_FILE_PATH in `cat ${RESTORE_FILE_PATH_LIST}`
  do
    TARGET_FILE_PATH=${DAV_RESTORE_TARGET_DIR}/${RESTORE_FILE_PATH}
    /bin/mkdir -p -- ${TARGET_FILE_PATH%/*} 2>${RESTORE_ERROR_MESSAGE} && \
    /bin/cp -p -- ${DAV_WORK_SPACE}/${RESTORE_FILE_PATH} ${TARGET_FILE_PATH} 2>${RESTORE_ERROR_MESSAGE}
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to write WebDav file into PCS. Process aborted. see error message [${RESTORE_ERROR_MESSAGE}]"
      exit 1
    fi
  done

  rm -f ${RESTORE_ERROR_MESSAGE}

  outputInfoLog "Completed restore count : ${OFFSET_COUNT}/${RESTORE_DAV_COUNT}."
}

# メイン

# WebDavリストア
# 処理開始ログの出力
outputInfoLog "Starting WebDav data restoration.  UnitUser: ${UNIT_USER_NAME}  Cel ID: ${CELL_ID}  Target Date: ${RESTORE_DATE}"

# TODO ★ 復元対象バックアップファイルの存在チェック ★


# リストア対象のDavファイルの件数を取得する
MYSQL_CMD="/usr/bin/mysql -u ${MYSQL_USER} --password=${MYSQL_PASSWORD} -h ${MYSQL_WORK_HOST} -P ${MYSQL_WORK_PORT}"
RESTORE_DAV_COUNT=`${MYSQL_CMD} ${INDEX_NAME} --skip-column-names -e "select count(*) from TMP_DAV_NODE where cell_id='${CELL_ID}' and node_type='dav.file';"`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to connect MySQL work Instance. Process aborted."
    exit 1
  fi
  if [ ${RESTORE_DAV_COUNT} -eq 0 ]; then
    outputInfoLog "No WevDav file to restore."
    # スクリプト終了ログ
    outputInfoLog "WebDav data restoration is completed. Proceeding..."
    exit 0
  fi


outputInfoLog "Restore WebDav File Count : ${RESTORE_DAV_COUNT}."
outputInfoLog "Restore WebDav File restore limit Count : ${LIMIT_COUNT}."

# 指定された件数分に分割してリストア対象のファイルパス一覧を作成する
OFFSET_COUNT=0
RESTORE_REMAIN_COUNT=${RESTORE_DAV_COUNT}

# テンポラリファイルの初期化
rm -f ${RESTORE_ID_LIST} ${RESTORE_FILE_PATH_LIST}

while :
do

    # ワークテーブルからDavIDを取得する($1:取得開始行数、$2:取得する件数)
    read_david_from_work_table ${OFFSET_COUNT} ${LIMIT_COUNT}
    OFFSET_COUNT=`expr ${OFFSET_COUNT} + ${LIMIT_COUNT}`

    if [ ${OFFSET_COUNT} -gt ${RESTORE_DAV_COUNT} ]; then
      OFFSET_COUNT=${RESTORE_DAV_COUNT}
    fi

    for DAV_FILE in `cat ${RESTORE_ID_LIST}`
    do
        # DavファイルIDを XX/YY/XXYYZZZZZZZZ に変換する($1:取得したDavリスト)
        transformation_webdav_id ${DAV_FILE}
    done

    outputInfoLog "Get restore dav file id list. [${OFFSET_COUNT}/${RESTORE_DAV_COUNT}]"

    RESTORE_REMAIN_COUNT=`expr ${RESTORE_REMAIN_COUNT} - ${LIMIT_COUNT}`
    if [ ${RESTORE_REMAIN_COUNT} -le 0 ]
    then
      break
    fi

    # 少し待つ
    /bin/sleep ${_SLEEP_PERIOD_IN_SEC}
done

# tarコマンドで対象CellのWebDavファイルを取り出してリストアする
restore_webdav

# テンポラリファイルの削除
rm -f ${RESTORE_ID_LIST} ${RESTORE_FILE_PATH_LIST}

# スクリプト終了ログ
outputInfoLog "WebDav data restoration is completed. Proceeding..."

exit 0
