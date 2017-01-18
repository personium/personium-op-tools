#!/bin/sh
##
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

# dc1-cellRestore.sh - セル単位でデータリストアを実施する。
# 1.リストア対象(以下の順でリストアを実施する)
#   ・MySQL
#   ・Elasticsearch
#   ・WebDAV
#   ・EventLog
# 2.パラメータ
#   ・-u <UnitUser名> リストア対象のユニットユーザ名
#   ・-c <Cell名>     リストア対象のセル名
#   ・-d <Backup日>   リストア対象のバックアップデータの日付
# 3.復帰コード
#   ・0  正常終了
#   ・1  異常終了（パラメータ誤り）
#   ・2  異常終了

DEBUG=
export BASE_DIR=/fj/dc-cell-restore
export TOOL_DIR=${BASE_DIR}/tools
export CONF_PATH=/fj/dc-config.properties
export LOCK_PATH=${BASE_DIR}/dc-cell-restore.lock
export JAVA_HOME=/opt/jdk
export PATH=$JAVA_HOME/bin:$PATH  

## 1.準備

# プロパティファイル読み込み
. ${TOOL_DIR}/dc1-readPropertyFile.sh
# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

## 1.1 オプションチェック
if [ $# -eq 0 ]; then
  outputErrorLog "Usage: dc1-cellRestore.sh -u <unituser-name> -c <cell-name> -d <restore-target-date>"
  exit 1
fi

while getopts u:c:d: opt
do
  case ${opt} in
    u) UNIT_USER="${OPTARG}" ;;
    c) CELL_NAME="${OPTARG}" ;;
    d) TARGET_DATE="${OPTARG}" ;;
    *) outputErrorLog "Usage: dc1-cellRestore.sh -u <unituser-name> -c <cell-name> -d <restore-target-date>" ; exit 1 ;;
  esac
done
outputInfoLog "Parameters :"
outputInfoLog '-----------------------------'
outputInfoLog "-u=${UNIT_USER}"
outputInfoLog "-c=${CELL_NAME}"
outputInfoLog "-d=${TARGET_DATE}"
outputInfoLog '-----------------------------'

# オプション未定義チェック
if [ -z ${UNIT_USER} ]; then
  outputErrorLog "Mandatory parameter '-u' is not specified. Process aborted."
  exit 1
fi
if [ -z ${CELL_NAME} ]; then
  outputErrorLog "Mandatory parameter '-c' is not specified. Process aborted."
  exit 1
fi
if [ -z ${TARGET_DATE} ]; then
  outputErrorLog "Mandatory parameter '-d' is not specified. Process aborted."
  exit 1
fi

## 1.2 プロパティチェック
${DEBUG} sh ${TOOL_DIR}/dc1-propertyCheck.sh
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # 多重起動時、ロック失敗時のメッセージは出力済み
  exit ${RET_CODE}
fi

## 1.3 ツール群の存在チェック
#  TODO: 不要と思われる


## 2.多重起動チェック
${DEBUG} sh ${TOOL_DIR}/dc1-prohibitMultiProcessInvocation.sh ${LOCK_PATH}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # 多重起動時、ロック失敗時のメッセージは出力済み
  exit ${RET_CODE}
fi

## 開始ログ出力
outputInfoLog "Cell restore is started.  Unit User: ${UNIT_USER}  Cell Name: ${CELL_NAME}  Target Date: ${TARGET_DATE}"


## 3.参照モードチェック
${DEBUG} sh ${TOOL_DIR}/dc1-checkReferenceOnlyMode.sh ${UNIT_USER}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み(ロック解放)
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
fi

## 4.リストア対象セルの非存在チェック
${DEBUG} sh ${TOOL_DIR}/dc1-checkCellAbsenceOnElasticsearch.sh ${CELL_NAME}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み(ロック解放)
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
fi

## 5.Memcached(cache用)の全キャッシュデータクリア
${DEBUG} sh ${TOOL_DIR}/dc1-clearMemcache.sh
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み(ロック解放)
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
fi

##
## これ以降のエラー時はデータクリアが必要なため
## ロックは解放せずに終了する。
##

## 6.リストア対象セルのMySQLデータ削除
${DEBUG} sh ${TOOL_DIR}/dc1-invokeCellSweep.sh
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 7.リストア用データのコピー
${DEBUG} sh ${TOOL_DIR}/dc1-prepareRestoreSource.sh ${UNIT_USER} ${TARGET_DATE}
RET_CODE=${?}
if [ ${RET_CODE} -eq 2 ]; then
  # #32659 UnitUser名や日付の指定誤りに起因する場合は再実行を容易にするため、ロックファイルを削除
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
elif [ ${RET_CODE} -ne 0 ]; then
  # コピー失敗などの復旧が必要な場合、ロックファイルは削除しない
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 8.MySQLワークインスタンス起動
${DEBUG} sh ${TOOL_DIR}/dc1-startRestoreDB.sh
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 9.セルリストア
## 9.1 MySQLワークインスタンスへCellIDの取得
outputInfoLog "Looking up Cell Id for Unit User: ${UNIT_USER}  Cell Name: ${CELL_NAME}"
CELL_ID=`${DEBUG} sh ${TOOL_DIR}/dc1-retrieveCellId.sh ${UNIT_USER} ${CELL_NAME}`
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # 異常時には、Cell IDの代わりにエラーメッセージが入っている。
  outputErrorLog "${CELL_ID}"

  # #32659 パラメタで指定したセル名が誤っていた場合、再実行を容易にするためにごみデータを削除、ロック解放
  ${DEBUG} sh ${TOOL_DIR}/dc1-disposeGarbage.sh ${UNIT_USER} ${TARGET_DATE}
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
fi
outputInfoLog "Looked up Cell Id: ${CELL_ID}  for Unit User: ${UNIT_USER}  Cell Name: ${CELL_NAME}"

## 9.2 MySQLへのENTITY/LINK/DAVのリストア
MYSQL_COUNT_PER_LOOP=1000
${DEBUG} sh ${TOOL_DIR}/dc1-restoreMySQLPhase1.sh ${UNIT_USER} ${CELL_ID} ${MYSQL_COUNT_PER_LOOP}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 9.3 ElasticsearchへのENTITY/LINK/DAVのリストア
ES_COUNT_PER_LOOP=1000
${DEBUG} sh ${TOOL_DIR}/dc1-restoreElasticsearchPhase1.sh ${UNIT_USER} ${CELL_ID} ${ES_COUNT_PER_LOOP}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 9.4 WebDAVのリストア
DAV_COUNT_PER_LOOP=10000
SLEEP_PERIOD_PER_LOOP_IN_SEC=1
${DEBUG} sh ${TOOL_DIR}/dc1-restoreDavFile.sh ${UNIT_USER} ${CELL_ID} ${TARGET_DATE} ${DAV_COUNT_PER_LOOP} ${SLEEP_PERIOD_PER_LOOP_IN_SEC}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 9.5 EventLogのリストア
${DEBUG} sh ${TOOL_DIR}/dc1-restoreEventlog.sh ${UNIT_USER} ${CELL_ID} ${TARGET_DATE}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 9.6 MySQLへのCELLのリストア
${DEBUG} sh ${TOOL_DIR}/dc1-restoreMySQLPhase2.sh ${UNIT_USER} ${CELL_ID}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 9.7 ElasticsearchへのCELLのリストア
${DEBUG} sh ${TOOL_DIR}/dc1-restoreElasticsearchPhase2.sh ${UNIT_USER} ${CELL_ID}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 10. リストア対象データ削除
${DEBUG} sh ${TOOL_DIR}/dc1-disposeGarbage.sh ${UNIT_USER} ${TARGET_DATE}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 11. MySQLワークインスタンス停止
${DEBUG} sh ${TOOL_DIR}/dc1-stopRestoreDB.sh 
RET_CODE=${?}
if [ ${RET_CODE} -eq 1 ]; then
  # MySQLワークインスタンスが既に停止済だった。
  # ただしここまでの処理が正常に終了しているため、以降の処理は継続する。
  outputWarnLog "MySQL process might not be stopped or already stopped. However it will not affect to rest of the script, so script will be continued."
fi

## 12. 整合性チェック
${DEBUG} sh ${TOOL_DIR}/dc1-invokeDiffValidation.sh ${UNIT_USER} ${CELL_ID}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi

## 13. MySQLスレーブ状態チェック
${DEBUG} sh ${TOOL_DIR}/dc1-checkMySQLSlaveStatus.sh
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abortWithReleaseLock ${RET_CODE} ${LOCK_PATH}
fi

## 14. 多重起動制御用ロック解放
releaseLock ${LOCK_PATH}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  # エラー時のメッセージは出力済み
  abort ${RET_CODE}
fi


## 終了ログ出力
outputInfoLog "Cell restore is completed. Unit User: ${UNIT_USER}  Cell Name: ${CELL_NAME}  Target Date: ${TARGET_DATE}"
exit 0
