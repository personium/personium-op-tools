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


# プロパティファイル読込
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh


# オプション設定
#    $1:ユニットユーザ名
#    $2:CellID
#    $3:リストア対象日付
UNIT_USER_NAME=$1
CELL_ID=$2
RESTORE_DATE=$3

if [ $# -lt 3 ]; then
  outputErrorLog "Required parameter is missing. Process aborted."
  exit 1
fi


EVLOG_RESTORE_TARGET_DIR=`getProp "com.fujitsu.dc.core.eventlog.basedir"`
EVLOG_WORK_SPACE=`getProp "com.fujitsu.dc.core.restore.workspace.eventlog.dir"`
EVLOG_BKUP_FILE_PREFIX=`getProp "com.fujitsu.dc.core.backup.eventlog.prefix"`

RESTORE_ERROR_MESSAGE="/tmp/restore_eventlog_error_message"


# Eventログファイル関連
FILE_PATH=



# CellIDを XX/YY/XXYYZZZZZZZZ に変換する
function transformCellIdToFilePath() {
  SUB_DIR=`echo $1 | sed -e 's/^\(..\)\(..\)\(.*\)$/\1\/\2/'`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to transformation Cell ID($1). Process aborted."
    exit 1
  fi

  FILE_PATH=${UNIT_USER_NAME}/${SUB_DIR}/$1
}

# tarコマンドで対象CellのEventLogディレクトリを取り出してリストアする
# TODO リストア対象バックアップディレクトリのパスをフルパスで指定すること
function restore_event_log() {
  # eventログバックアップディレクトリが存在するかチェック
  if [ ! -d ${EVLOG_WORK_SPACE}/${UNIT_USER_NAME} ]; then
    outputErrorLog "Could not find back up file to restore. Process aborted. "
    exit 1
  fi

  if [ -d ${EVLOG_WORK_SPACE}/${FILE_PATH} ]; then
    outputInfoLog "Number of files to restore : ${EVENTLOG_COUNT}"

    # eventログのリストア
    TARGET_FILE_PATH=${EVLOG_RESTORE_TARGET_DIR}/${FILE_PATH}
    /bin/mkdir -p -- ${TARGET_FILE_PATH} 2>${RESTORE_ERROR_MESSAGE} && \
    /bin/cp -pr -- ${EVLOG_WORK_SPACE}/${FILE_PATH} ${TARGET_FILE_PATH%/*} 2>${RESTORE_ERROR_MESSAGE}
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to write event log file into PCS. Process aborted. see error message [${RESTORE_ERROR_MESSAGE}]"
      exit 1
    fi
    rm -f ${RESTORE_ERROR_MESSAGE}
  else
    # 対象のCellのイベントログがバックアップファイルに存在しない場合は処理をスキップ
    outputInfoLog "No eventlog to restore."
    outputInfoLog "Eventlog data restoration is completed. Proceeding... "
    exit 0

  fi
}

# =====================================
# メイン
# =====================================
# eventログリストア開始ログ出力
outputInfoLog "Starting eventlog restoration. UnitUser: ${UNIT_USER_NAME}  Cell ID: ${CELL_ID}  Target Date: ${RESTORE_DATE}"

# CellIDを XX/YY/XXYYZZZZZZZZ に変換する($1:CellID)
transformCellIdToFilePath ${CELL_ID}
outputInfoLog "Event log Path: ${FILE_PATH}"

# tarコマンドで対象CellのEventログを取り出してリストアする
restore_event_log

outputInfoLog "Eventlog data restoration is completed. Proceeding... "


exit 0
