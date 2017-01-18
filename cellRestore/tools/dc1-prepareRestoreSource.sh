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

# dc1-prepareRestoreSource.sh - バックアップファイル存在チェック～バックアップデータ複写
# 引数：
# ・ユニットユーザ名
# ・リストア対象バックアップデータの日付(YYYYMMDD)
#
# 復帰コード：
# ・0 正常終了
# ・1 DISK空き領域不足
# ・2 リストア用データコピー失敗
# ・3 パラメータ異常

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

outputInfoLog "Start copying restore source files into workspace. UnitUser: ${1}  Target Date: ${2}"


# 引数チェック
if [ $# -ne 2 ]; then
  outputErrorLog "Usage: dc1-prepareRestoreSource.sh <unituser-name> <restore-target-date>"
  exit 1
fi

. ${TOOL_DIR}/dc1-readPropertyFile.sh


# プロパティファイルからの読み込み
UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`
MYSQL_PREFIX=`getProp "com.fujitsu.dc.core.backup.mysql.prefix"`
MYSQL_BACKUP_BASE_DIR=`getProp "com.fujitsu.dc.core.backup.mysql.dir"`
MYSQL_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.mysql.dir"`
WEBDAV_BACKUP_PREFIX=`getProp "com.fujitsu.dc.core.backup.dav.prefix"`
WEBDAV_BACKUP_BASE_DIR=`getProp "com.fujitsu.dc.core.backup.dav.dir"`
WEBDAV_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.webdav.dir"`
EVENTLOG_BACKUP_PREFIX=`getProp "com.fujitsu.dc.core.backup.eventlog.prefix"`
EVENTLOG_BACKUP_BASE_DIR=`getProp "com.fujitsu.dc.core.backup.eventlog.dir"`
EVENTLOG_RESTORE_BASE_DIR=`getProp "com.fujitsu.dc.core.restore.workspace.eventlog.dir"`
MYSQL_BACKUP_ARCHIVE=`getProp "com.fujitsu.dc.core.restore.mysql.archive.backup"`

# 1. バックアップデータの存在チェック
# MySQL
###  入力パラメタ ${1} は 記号変換していない。(e.g '-' => @002 ) このため変換が必要
RAW_MYSQL_UNITUSER_NAME=`convertUnitUserDBtoRawMySQLName ${1}`
MYSQL_BACKUP_DIR=${MYSQL_BACKUP_BASE_DIR}/${MYSQL_PREFIX}_${2}/${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME}
MYSQL_ARCHIVE_BACKUP_PATH=${MYSQL_BACKUP_BASE_DIR}/${MYSQL_PREFIX}_${2}.tar.gz

outputInfoLog "Checking the existence of backup data. Unit User: ${1}  Target Date: ${2}"
# MySQL
if [ "${MYSQL_BACKUP_ARCHIVE}" = "true" ]; then
  isBackupExist=`tar tvzf ${MYSQL_ARCHIVE_BACKUP_PATH} | egrep '^d' | egrep "${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME}/" | wc -l`
  if [ ${isBackupExist} -eq 0 ]; then
    outputErrorLog "Target backup file for DB does not exist in ${MYSQL_ARCHIVE_BACKUP_PATH}. [${MYSQL_BACKUP_DIR}] Process aborted."
    exit 2
  fi
elif [ ! -d ${MYSQL_BACKUP_DIR} ]; then
  outputErrorLog "Target backup file for DB does not exist. [${MYSQL_BACKUP_DIR}] Process aborted."
  exit 2
fi
# WebDAV
WEBDAV_BACKUP_FILE_PATH="${WEBDAV_BACKUP_BASE_DIR}/dav.${2}/${1}"
if [ ! -d ${WEBDAV_BACKUP_FILE_PATH} ]; then
  outputErrorLog "Target backup file for WebDav does not exist. [${WEBDAV_BACKUP_FILE_PATH}] Process aborted."
  exit 2
fi
# EventLog
EVENTLOG_BACKUP_FILE_PATH="${EVENTLOG_BACKUP_BASE_DIR}/eventlog.${2}/${1}"
if [ ! -d ${EVENTLOG_BACKUP_FILE_PATH} ]; then
  outputErrorLog "Target backup file for Eventlog does not exist. [${EVENTLOG_BACKUP_FILE_PATH}] Process aborted."
  exit 2
fi
outputInfoLog "Confirmed the existence of backup data. Proceeding..."


outputInfoLog "Checking the existence of restore workspace."
# 2. リストア用データディレクトリの存在チェック
# MySQL
MYSQL_RESTORE_DIR=${MYSQL_RESTORE_BASE_DIR}
if [ ! -d ${MYSQL_RESTORE_DIR} ]; then
  outputErrorLog "Data directory not found for restore DB. [${MYSQL_RESTORE_DIR}] Process aborted."
  exit 2
fi
# WebDAV
if [ ! -d ${WEBDAV_RESTORE_BASE_DIR} ]; then
  outputErrorLog "Data directory not found for restore WebDav. [${WEBDAV_RESTORE_BASE_DIR}] Process aborted."
  exit 2
fi
# EventLog
if [ ! -d ${EVENTLOG_RESTORE_BASE_DIR} ]; then
  outputErrorLog "Data directory not found for restore EventLog. [${EVENTLOG_RESTORE_BASE_DIR}] Process aborted."
  exit 2
fi
outputInfoLog "Confirmed the existence of restore workspace, Proceeding..."


outputInfoLog "Checking existence of the previous backup data."
# 3. 過去にリストアした際のリストア用データ存在チェック
# MySQL
##  入力パラメタ は 記号変換したものを使用。(e.g '-' => @002 )
if [ -e ${MYSQL_RESTORE_DIR}/${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME} ]; then
  outputErrorLog "Previous backup data for DB already exists in workspace. Process aborted."
  exit 2
fi
# WebDAV
WEBDAV_RESTORE_FILE_PATH=${WEBDAV_RESTORE_BASE_DIR}/${1}
if [ -e ${WEBDAV_RESTORE_FILE_PATH} ]; then
  outputErrorLog "Previous backup data for WebDav already exists in workspace. Process aborted."
  exit 2
fi
# EventLog
EVENTLOG_RESTORE_FILE_PATH=${EVENTLOG_RESTORE_BASE_DIR}/${1}
if [ -e ${EVENTLOG_RESTORE_FILE_PATH} ]; then
  outputErrorLog "Previous backup data for Eventlog already exists in workspace. Process aborted."
  exit 2
fi
outputInfoLog "Confirmed the cleared of data directory for restore, Proceeding..."


outputInfoLog "Checking the diskspace for DB restoration."
# 4. リストア用データを格納するパーティションの空き領域チェック
# TODO 現在は空き領域0で判定しているが、本来は余裕を持ったチェックを行う必要がある
# MySQL
MYSQL_FREE_SPACE=`df -P ${MYSQL_RESTORE_BASE_DIR} | tail -1 | awk '{print $4}'`
if [ "${MYSQL_BACKUP_ARCHIVE}" = "true" ]; then
  MYSQL_USED=`tar tvfz ${MYSQL_ARCHIVE_BACKUP_PATH} | egrep -v '^d' | grep ${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME} | awk '{sum = sum + $3} END{printf "%d",sum/1000+1}'`
else
  MYSQL_USED=`du -s ${MYSQL_BACKUP_DIR} | awk '{print $1}'`
fi
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to calculation of target backup size. Process aborted."
  exit 2
fi
MYSQL_AVAILABLE=`expr ${MYSQL_FREE_SPACE} - ${MYSQL_USED}`
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to calculation of disk enough space. Process aborted."
  exit 2
fi
if [ ${MYSQL_AVAILABLE} -le 0 ]; then
  outputErrorLog "Not enough space left on the disk volume for restore MySQL. Process aborted."
  exit 2
fi
outputInfoLog "Sufficient disk space exists for restore MySQL. Proceeding..."

# WebDAV/EventLog
# WebDAVとEventLogはハードリンクを作成するので、リストア用データ領域のデータ量は増えないため
# チェックしない（ディレクトリ分は増加する）。

outputInfoLog "Copying the source data for DB into restore workspace."
# 5. リストア用データをコピーする
# MySQL
if [ "${MYSQL_BACKUP_ARCHIVE}" = "true" ]; then
  /bin/tar zxf ${MYSQL_ARCHIVE_BACKUP_PATH} -C ${MYSQL_RESTORE_DIR}/ ${UNIT_PREFIX}_${RAW_MYSQL_UNITUSER_NAME}
  if [ ${?} -ne 0 ]; then
    outputErrorLog "Failed to unzip backup archive (DB) into restore workspace. Process aborted."
    exit 3
  fi
else
  /bin/cp -rp ${MYSQL_BACKUP_DIR} ${MYSQL_RESTORE_DIR}
  if [ ${?} -ne 0 ]; then
    outputErrorLog "Failed to copy backup data (DB) into restore workspace. Process aborted."
    exit 3
  fi
fi

outputInfoLog "Copying the source data for WebDav into restore workspace."
# WebDav
WEBDAV_RESTORE_DIR=${WEBDAV_RESTORE_BASE_DIR}/
/bin/mkdir -p ${WEBDAV_RESTORE_DIR}
if [ ${?} -ne 0 ]; then
  outputErrorLog "Failed to copy backup data (WebDav) into restore workspace. Process aborted."
  exit 3
fi
/bin/cp -lpr ${WEBDAV_BACKUP_FILE_PATH} ${WEBDAV_RESTORE_DIR}
if [ ${?} -ne 0 ]; then
  outputErrorLog "Failed to copy backup data (WebDav) into restore workspace. Process aborted."
  exit 3
fi

outputInfoLog "Copying the source data for eventlog into restore workspace."
# EentLog
EVENTLOG_RESTORE_DIR=${EVENTLOG_RESTORE_BASE_DIR}/
/bin/mkdir -p ${EVENTLOG_RESTORE_DIR}
if [ ${?} -ne 0 ]; then
  outputErrorLog "Failed to copy backup data (Eventlog) into restore workspace. Process aborted."
  exit 3
fi
/bin/cp -lpr ${EVENTLOG_BACKUP_FILE_PATH} ${EVENTLOG_RESTORE_DIR}
if [ ${?} -ne 0 ]; then
  outputErrorLog "Failed to copy backup data (Eventlog) into restore workspace. Process aborted."
  exit 3
fi
outputInfoLog "Copying restore source files into workspace is completed. Proceeding..."

#outputInfoLog "end"
exit 0
