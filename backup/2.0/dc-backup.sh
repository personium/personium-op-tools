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
ROOT_DIR=
DATE=`/bin/date +%Y%m%d`
BACKUP_LOG=${ROOT_DIR}/fj/dc-backup/log/dc_backup.log
BACKUP_LOG_OLD=${BACKUP_LOG}.`/bin/date +%Y%m%d -d '1 days ago'`
LOCK_FILE=${ROOT_DIR}/fj/dc-backup/dc-backup.lock

# MySQL関連
MYSQL_SRC_DIR=${ROOT_DIR}/fj/mysql/data
MYSQL_WORK_DIR=${ROOT_DIR}/fj/mysql/data_backup.tmp
MYSQL_DST_DIR=${ROOT_DIR}/fj/mysql/data_${DATE}


# 処理中止（ロックを開放して終了）
function abort() {
  remove_temporary_backup
  if [ -f ${LOCK_FILE} ]; then
    releaseLock
  fi
  exit $1
}

# 二重起動抑止のためにロックを解放
## ロックの解放に失敗した場合は、ログを出力して終了する
function releaseLock() {
  /bin/rm -f ${LOCK_FILE} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to release lock for the double start control."
    /bin/rm -f ${LOCK_FILE} >> ${BACKUP_LOG} 2>&1
    exit 1
  fi
}

# INFOログ出力
function outputInfoLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [INFO ] $1" >> ${BACKUP_LOG}
}

# WARNログ出力
function outputWarnLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [WARN ] $1" >> ${BACKUP_LOG}
}

# ERRORログ出力
function outputErrorLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [ERROR] $1" >> ${BACKUP_LOG}
}

# スクリプト終了ログ
function outPutScriptEndlog() {
  outputInfoLog "UnitUser backup end."
  outputInfoLog "------------------------------------------"
}

# プロパティファイルを読む込む
function read_properties() {
  if [ ! -f $1 ]; then
    outputWarnLog "Invalid argument[-p]."
    abort 1
  fi 

  UNIT_PREFIX=`/bin/grep 'com.fujitsu.dc.core.es.unitPrefix' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.es.unitPrefix' is not defined."
    abort 1
  fi 
  if [ -z ${UNIT_PREFIX} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.es.unitPrefix' is not defined."
    abort 1
  fi 
  MYSQL_USER=`/bin/grep 'com.fujitsu.dc.core.mysql.backup.user.name' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.backup.user.name' is not defined."
    abort 1
  fi 
  if [ -z ${MYSQL_USER} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.backup.user.name' is not defined."
    abort 1
  fi 
  MYSQL_PASS=`/bin/grep 'com.fujitsu.dc.core.mysql.backup.user.password' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.backup.user.password' is not defined."
    abort 1
  fi 
  if [ -z ${MYSQL_PASS} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.backup.user.password' is not defined."
    abort 1
  fi 
  MYSQL_HOST=`/bin/grep 'com.fujitsu.dc.core.mysql.slave.host' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.slave.host' is not defined."
    abort 1
  fi 
  if [ -z ${MYSQL_HOST} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.slave.host' is not defined."
    abort 1
  fi 
  MYSQL_PORT=`/bin/grep 'com.fujitsu.dc.core.mysql.slave.port' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.slave.port' is not defined."
    abort 1
  fi 
  if [ -z ${MYSQL_PORT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.slave.port' is not defined."
    abort 1
  fi 
  BACKUP_GENERATION=`/bin/grep 'com.fujitsu.dc.core.backup.count' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.count' is not defined."
    abort 1
  fi 
  if [ -z ${BACKUP_GENERATION} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.count' is not defined."
    abort 1
  fi 
  SOPOS_SPLIT_SIZE=`/bin/grep 'com.fujitsu.dc.core.backup.splitSize' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.splitSize' is not defined."
    abort 1
  fi 
  if [ -z ${SOPOS_SPLIT_SIZE} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.splitSize' is not defined."
    abort 1
  fi 
  # MySQLバックアップの圧縮オプション
  ARCHIVE_ENABLE=`/bin/grep 'com.fujitsu.dc.core.backup.mysql.archive.enable' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    ARCHIVE_ENABLE='false'
  fi 
  if [ -z ${ARCHIVE_ENABLE} ]; then
    ARCHIVE_ENABLE='false'
  fi 
  # Davファイルのバックアップ元ディレクトリ
  BACKUP_SRC_DAV_ROOT=`/bin/grep 'com.fujitsu.dc.core.webdav.basedir' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.webdav.basedir' is not defined."
    abort 1
  fi 
  if [ -z ${BACKUP_SRC_DAV_ROOT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.webdav.basedir' is not defined."
    abort 1
  fi 
  # Davファイルのバックアップ先ディレクトリ
  BACKUP_DEST_DAV_ROOT=`/bin/grep 'com.fujitsu.dc.core.backup.dav.dir' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.dav.dir' is not defined."
    abort 1
  fi 
  if [ -z ${BACKUP_DEST_DAV_ROOT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.dav.dir' is not defined."
    abort 1
  fi 
  # EventLogのバックアップ元ディレクトリ
  BACKUP_SRC_EVLOG_ROOT=`/bin/grep 'com.fujitsu.dc.core.eventlog.basedir' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.eventlog.basedir' is not defined."
    abort 1
  fi 
  if [ -z ${BACKUP_SRC_EVLOG_ROOT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.eventlog.basedir' is not defined."
    abort 1
  fi 
  # EventLogのバックアップ先ディレクトリ
  BACKUP_DEST_EVLOG_ROOT=`/bin/grep 'com.fujitsu.dc.core.backup.eventlog.dir' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ $? -ne 0 ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.eventlog.dir' is not defined."
    abort 1
  fi 
  if [ -z ${BACKUP_DEST_EVLOG_ROOT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.eventlog.dir' is not defined."
    abort 1
  fi 

  # 読み込んだプロパティファイルからmysqlコマンドを生成
  MYSQL_CMD="/usr/bin/mysql -u ${MYSQL_USER} --password=${MYSQL_PASS} -h ${MYSQL_HOST} --port=${MYSQL_PORT}"
}

# バックアップ先ディレクトリを作成する
function create_directory() {
  # WebDAV用バックアップディレクトリの作成
  if [ ! -d ${BACKUP_DEST_DAV_ROOT} ]; then
    /bin/mkdir -p ${BACKUP_DEST_DAV_ROOT} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to make backup directory. (${BACKUP_DEST_DAV_ROOT})"
      return 1
    fi 
  fi 
  # イベントログ用バックアップディレクトリの作成
  if [ ! -d ${BACKUP_DEST_EVLOG_ROOT} ]; then
    /bin/mkdir -p ${BACKUP_DEST_EVLOG_ROOT} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to make backup directory. (${BACKUP_DEST_EVLOG_ROOT})"
      return 1
    fi 
  fi 
  outputInfoLog "Create backup directory."
}

# rsyncの --link-dest オプションで利用する、新バックアップと比較対象ディレクトリの相対パスを返す。
## ${1}：バックアップルートディレクトリ
## ${2}：過去のバックアップディレクトリのプリフィクス
function get_previous_backup_relative_path() {
  BACKUP_BASE_DIR=${1}
  BACKUP_DIR_PREFIX=${2}

  pushd ${BACKUP_BASE_DIR} > /dev/null 2>&1

  # link-destで比較対象とするディレクトリ(最終バックアップ)の確認
  RESULT=""
  BACKUP_COUNT=`/bin/ls -1d ./${BACKUP_DIR_PREFIX}.* 2> /dev/null | /bin/egrep "\./${BACKUP_DIR_PREFIX}\.[0-9]{8}$" | /bin/egrep -v "\./${BACKUP_DIR_PREFIX}\.${DATE}" | /usr/bin/wc -l`
  if [ 0 -ne ${BACKUP_COUNT} ]; then
    RESULT=`/bin/ls -1d ./${BACKUP_DIR_PREFIX}.* 2> /dev/null | /bin/egrep "\./${BACKUP_DIR_PREFIX}\.[0-9]{8}$" | /bin/egrep -v "\./${BACKUP_DIR_PREFIX}\.${DATE}" | /usr/bin/tail -1`
    # 相対パスに変換したいため、ひとつだけ "." をつける。
    RESULT=".${RESULT}"
  fi

  popd > /dev/null 2>&1
  echo ${RESULT}
}



# MySQL Slaveのレプリケーション停止
function mysql_replication_stop() {
  ${MYSQL_CMD} -e "STOP SLAVE;" >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to connect MySQL slave server."
    abort 1
  fi
  sleep 5
  STATUS=`${MYSQL_CMD} -e "SHOW SLAVE STATUS\G" | \
  /bin/egrep 'Slave_IO_Running|Slave_SQL_Running' | sed -s 's/ //g' | sed -s 's/^.*://g'`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to connect MySQL slave server."
    abort 1
  fi
  counter=`expr 0`
  for stat in $STATUS
  do
    if [ "${stat}" = "Yes" ]; then
      outputErrorLog "Failed to stop MySQL slave server."
      abort 1
    fi
    counter=`expr ${counter} + 1`
  done
  if [ ${counter} -ne 2 ]; then
      outputErrorLog "Failed to stop MySQL slave server."
      abort 1
  fi
}

# MySQL Slaveのレプリケーション再開
function mysql_replication_start() {
  ${MYSQL_CMD} -e "START SLAVE;" >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to connect MySQL slave server."
    abort 1
  fi

  wait_slave_start

}

# MYSQLバックアップ
## ここでは一時バックアップ先に出力する。
function exec_mysql_backup() {
  outputInfoLog "MySQL backup start."

  ## mysqlのデータディレクトリの存在チェック
  if [ ! -d ${MYSQL_SRC_DIR} ]; then
    outputErrorLog "No data for backup. path=[${MYSQL_SRC_DIR}]"
    return 1
  fi

  ## mysqlのデータディレクトリをコピーする
  if [ "${ARCHIVE_ENABLE}" = "true" ]; then
    pushd ${MYSQL_SRC_DIR} > /dev/null 2>&1
    outputInfoLog "MySQL data archive start."
    /bin/tar zcf ${MYSQL_WORK_DIR} * >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to archive MySQL data directory. (${MYSQL_SRC_DIR})"
      return 1
    fi
    outputInfoLog "MySQL data archive end."
    popd > /dev/null 2>&1
  else
    /bin/cp -pr ${MYSQL_SRC_DIR} ${MYSQL_WORK_DIR} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to backup MySQL data directory. (${MYSQL_SRC_DIR})"
      return 1
    fi
  fi

  outputInfoLog "MySQL backup end."
}

# rsyncを実行し、一時バックアップ先ディレクトリをバックアップ元と同期する
## ${1}：ファイルのバックアップ先ルートディレクトリ
## ${2}：ファイルのバックアップ元ルートディレクトリ
## ${3}：--link-destオプションに指定する前回のバックアップディレクトリ(注: 新規バックアップとの相対パスでなければならない。)
##       nullの場合は --link-destオプションは生成しない。
### ディレクトリを再帰的に同期
### パーミッション、グループ、オーナー、タイムスタンプを保持したまま同期
### バックアップ元から削除されたファイルはバックアップ先からも削除する
function exec_file_rsync(){
  outputInfoLog "rsync start. To:${1}"

  # バックアップ先のディレクトリが存在しない場合、作成する。
  create_directory

  ## バックアップ対象のルートディレクトリが存在するかのチェック
  if [ ! -d ${2} ]; then
    outputErrorLog "No data for rsync. path=[${2}]"
    return 1
  fi

  pushd ${1} > /dev/null 2>&1

  # 当日以外の最新バックアップが第３引数に指定されている場合、--link-destオプションを生成。
  #   これにより最新バックアップから変更の無いファイルはハードリンクとしてバックアップされる。
  LINK_DEST_OPTION=""
  if [ ! -z ${3} ]; then
    LINK_DEST_OPTION="--link-dest ${3}"
  fi
  SOURCE_DIR=${2}
  BACKUP_DIR_PREFIX=`/usr/bin/readlink -f ${SOURCE_DIR} | sed -e "s/.*\///"`
  TARGET_BACKUP=${BACKUP_DIR_PREFIX}.backup.tmp

  /usr/bin/rsync -av --delete ${LINK_DEST_OPTION} ${SOURCE_DIR}/ ./${TARGET_BACKUP} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 -a $? -ne 24 ]; then
    ## エラーコード24はバックアップ中にファイル削除が行われた場合に発生する
    ## 削除されたファイルはバックアップする必要がないため、
    ## rsyncの実行結果としては「正常」として扱う
    outputErrorLog "Failed to rsync. To:${1}"
    popd > /dev/null 2>&1
    return 1
  fi
  popd > /dev/null 2>&1
  outputInfoLog "rsync end. To:${1}"
}

## MySQLのDBは存在するが、WebDav/Eventlogが存在しない
## ユニットユーザに対して空ディレクトリを作成する
## ${1}：ユニットユーザの一覧
## ${2}：ファイルのバックアップ先ルートディレクトリ
function check_unituser_data_directory() {
  for DB_NAME in ${1}
  do
    UNIT_USER_NAME=`echo ${DB_NAME} | sed -e "s/${UNIT_PREFIX}_//"`
    TARGET_UNIT_USER=${2}/${UNIT_USER_NAME}
    if [ ! -d ${TARGET_UNIT_USER} ]; then
      /bin/mkdir -p ${TARGET_UNIT_USER} >> ${BACKUP_LOG} 2>&1 &&
      /bin/chown 2070.2070 ${TARGET_UNIT_USER} >> ${BACKUP_LOG} 2>&1
      if [ $? -ne 0 ]; then
        outputErrorLog "Failed to make backup directory. (${TARGET_UNIT_USER})"
        return 1
      fi 
    fi
  done
}

# 指定されたパスにバックアップファイルを作成する
function store_output_dir_path() {
  outputInfoLog "Create new backup to [${OUTPUT_DIR_PATH}]."
  # -oオプションが指定された場合は、オプションで指定されたディレクトリにバックアップファイルを格納する
  # SOPOSへの格納は実施せず、バックアップの削除も行わない
  if [ -z ${OUTPUT_DIR_PATH} ]; then
    return;
  elif [ ! -d ${OUTPUT_DIR_PATH} ]; then
    outputWarnLog "Invalid argument[-o]."
    abort 1
  fi
  BACKUP_DEST_TAR_DIR=${OUTPUT_DIR_PATH}
  BACKUP_DEST_EVLOG_TAR_DIR=${OUTPUT_DIR_PATH}
}


# 一時バックアップの名前を正式名称に変名
# すべてのバックアップが正常終了した場合に、本関数を使用
function rename_temporary_backup() {

  BACKUP_DST=${1}
  BACKUP_WORK=${2}

  ## バックアップ先データの存在チェック
  ### 存在した場合は、削除しておく
  if [ -e ${BACKUP_DST} ]; then
    outputInfoLog "Backup directory already exsits. path=[${BACKUP_DST}]"
    /bin/rm -rf ${BACKUP_DST} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to remove backup directory."
      return 1
    fi
  fi
  ## 一時バックアップの名前を正式名称に変名
  /bin/mv ${BACKUP_WORK} ${BACKUP_DST} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to rename temporary backup directory. source path=[${BACKUP_WORK}] dest path=[${BACKUP_DST}]"
    return 1
  fi

}


# 一時バックアップディレクトリを削除
# バックアップ中に異常が発生した場合に、本関数を使用
function remove_temporary_backup() {

  DAV_WORK_DIR=${BACKUP_DEST_DAV_ROOT}/dav.backup.tmp
  EVLOG_WORK_DIR=${BACKUP_DEST_EVLOG_ROOT}/eventlog.backup.tmp

  outputInfoLog "Remove temporary backup directory start."

  /bin/rm -rf ${DAV_WORK_DIR} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to remove temporary backup directory. path=${DAV_WORK_DIR}"
  fi
  /bin/rm -rf ${EVLOG_WORK_DIR} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to remove temporary backup directory. path=${EVLOG_WORK_DIR}"
  fi
  /bin/rm -rf ${MYSQL_WORK_DIR} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to remove temporary backup directory. path=${MYSQL_WORK_DIR}"
  fi

  outputInfoLog "Remove temporary backup directory end."
}


# バックアップデータのローテート
# TODO バックアップをSPLITしたときのローテート実装
## ${1}：ファイルバックアップ先ディレクトリ
## ${2}：バックアップディレクトリ名のプリフィクス(e.g. "dav.YYYYMMDD" なら "dav")
function remove_backup() {
  if [ ! -d ${1} ]; then
    return;
  fi
  
  BACKUP_DIR_PREFIX=${2}

  FILE_LIST=`/bin/ls -1rd ${1}/${BACKUP_DIR_PREFIX}.* 2> /dev/null | /bin/egrep ".*/${BACKUP_DIR_PREFIX}\.[0-9]{8}$"`
  counter=`expr 1`
  for FILE in ${FILE_LIST}
  do
    if [ $counter -gt ${BACKUP_GENERATION} ]; then
      /bin/rm -rf ${FILE} >> ${BACKUP_LOG} 2>&1
      if [ $? -ne 0 ]; then
        outputWarnLog "Failed to remove old backup. (${FILE})"
      fi
    fi
    counter=`expr ${counter} + 1`
  done
}


# MySQLのバックアップデータのローテート
function remove_backup_formysql() {
  DIR_LIST=`/bin/ls -1dt ${MYSQL_SRC_DIR}_* 2>/dev/null | /bin/egrep "${MYSQL_SRC_DIR}_[0-9]{8}$|${MYSQL_SRC_DIR}_[0-9]{8}.tar.gz$"`
  counter=`expr 1`
  for DIR in ${DIR_LIST}
  do
    if [ $counter -gt ${BACKUP_GENERATION} ]; then
      /bin/rm -rf ${DIR} >> ${BACKUP_LOG} 2>&1
      if [ $? -ne 0 ]; then
        outputWarnLog "Failed to remove old backup(MySQL). (${DIR})"
      fi
    fi
    counter=`expr ${counter} + 1`
  done
}


## MySQLデーモンを起動して、数秒待ってからスレーブ状態を確認する
## 異常発生の場合は、このfunction内でシェルスクリプトを終了する
## 終了時にlockファイルも削除する
function mysqlstart() {
  # MySQL start
  outputInfoLog "MySQL start."

  /etc/init.d/mysql start >> ${BACKUP_LOG} 2>&1
  aliveres=`ps -ef | grep "mysqld" |
          grep -v grep | wc -l`
  if [ ${aliveres} -ne 2 ]; then
    outputErrorLog "MySQL start failed."
    abort 1
  fi

  wait_slave_start

}


# スレーブの起動完了待ち合わせ
function wait_slave_start() {
  # MySQL slave status check
  outputInfoLog "MySQL slave status check."
  sleep 5
  checkNumber=`expr 0`
  while :
  do
    `checkSlaveStatus`
    checkResult=$?
    if [ ${checkResult} -eq 0 ]; then
      outputInfoLog "MySQL slave status check finished. status:[OK]"
      break
    elif [ ${checkResult} -eq 2 ]; then
      outputErrorLog "MySQL slave status failed."
      /usr/bin/mysql -u root -p'c3s-innov_root' -e 'SHOW SLAVE STATUS\G' >> ${BACKUP_LOG}
      abort 1
    elif [ ${checkNumber} -ge 5 ]; then
      outputErrorLog "MySQL slave status failed."
      /usr/bin/mysql -u root -p'c3s-innov_root' -e 'SHOW SLAVE STATUS\G' >> ${BACKUP_LOG}
      abort 1
    fi
    checkNumber=`expr ${checkNumber} + 1`
    ## 次のチェックまでスリープさせる
    sleep 10
  done
}

## スレーブの状態を確認する。
## return 0: 正常終了 1:復旧可能な異常 2:復旧不可能な異常
##
function checkSlaveStatus() {
  local STATUS=`/usr/bin/mysql -u root -p'c3s-innov_root' -e 'SHOW SLAVE STATUS\G' | \
  /bin/egrep 'Slave_IO_Running|Slave_SQL_Running' | sed -s 's/ //g' | sed -s 's/^.*://g'`
  if [ $? -ne 0 ]; then
    outputErrorLog "MySQL slave connect failed."
    return 2
  fi
  ## チェック内容
  ## Slave_IO_RunningとSlave_SQL_Runningのステータスが両者ともに'Yes'であること
  local counter=`expr 0`
  for stat in $STATUS
  do
    if [ "${stat}" != "Yes" ]; then
      outputInfoLog "MySQL status invalid."
      return 1
    fi
    counter=`expr ${counter} + 1`
  done
  ## ステータスが2行分とれない場合（ありえない）
  if [ ${counter} -ne 2 ]; then
    outputErrorLog "MySQL status abnormal."
    /usr/bin/mysql -u root -p'c3s-innov_root' -e 'SHOW SLAVE STATUS\G' >> ${BACKUP_LOG}
    return 2
  fi
  return 0
}

## MySQLスレーブサーバのプロセスを停止する
function mysqlstop(){
  outputInfoLog "MySQL stop."
  /etc/init.d/mysql stop >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "MySQL stop failed."
    # slave start
    /usr/bin/mysql -u root -p'c3s-innov_root' -e'start slave;' >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "MySQL slave start failed."
    fi
    abort 1
  fi
}


#### メイン処理 #####
# 既存のログファイルを前日の日付を付加して退避する
## 前日の日付を付加したファイルが既に存在する場合は退避しない
## 退避に失敗した場合は、ログを出力し、処理を続行する
if [ ! -e ${BACKUP_LOG_OLD} ]; then
  if [ -e ${BACKUP_LOG} ]; then
    mv -f ${BACKUP_LOG} ${BACKUP_LOG_OLD} 2>&1
    if [ $? -ne 0 ]; then
      if [ ! -e ${BACKUP_LOG_OLD} ]; then
        outputWarnLog "UnitUser backup log file rename failed."
      fi
    fi
  fi
fi
outputInfoLog "UnitUser backup start."

# パラメータのパースを実施する
while getopts ":p:u:o:" ARGS
do
  case $ARGS in
  p )
    # プロパティファイルのパス
    PROPERTIES_FILE_PATH=$OPTARG
    ;;
  o )
    # 出力ファイルのパス
    OUTPUT_DIR_PATH=$OPTARG
    ;;
  :)
    outputWarnLog "[-$OPTARG] requires an argument."
    outPutScriptEndlog
    exit 1
    ;;
  esac
done

# -p パラメタは必須
outputInfoLog "Arguments list. -p [${PROPERTIES_FILE_PATH}] -o [${OUTPUT_DIR_PATH}]."
if [ -z "${PROPERTIES_FILE_PATH}" ]; then
  outputWarnLog "[-p] arguments is necessary."
  outPutScriptEndlog
  exit 1
fi

# ロックファイルが存在するか確認し、存在しない場合は作成する
## ロックファイルが存在する場合、ログを出力し終了する
if [ -f ${LOCK_FILE} ]; then
  outputInfoLog "UnitUser backup has already started."
  outPutScriptEndlog
  exit 0
fi
echo $$ > ${LOCK_FILE}

# -pオプションで渡されたdc-config.propertiesファイルから必要なプロパティを読み込む
read_properties ${PROPERTIES_FILE_PATH}

# -oオプションで渡されたディレクトリへ出力先を切り替える
store_output_dir_path

##### バックアップのディレクトリのプリフィクスを生成
##### 本実装では、バックアップ元の最終ディレクトリ名(dav, eventlog)
DAV_BACKUP_DIR_PREFIX=`/usr/bin/readlink -f ${BACKUP_SRC_DAV_ROOT} | sed -e "s/.*\///"`
EVLOG_BACKUP_DIR_PREFIX=`/usr/bin/readlink -f ${BACKUP_SRC_EVLOG_ROOT} | sed -e "s/.*\///"`

##### 当日分を除く、前回バックアップの有無確認：存在する場合、新バックアップとの相対パスが返る。
##### この結果を利用し、exec_file_rsync関数内で --link-destオプションの作成/削除を判定する。
PREVIOUS_DAV_BACKUP=`get_previous_backup_relative_path ${BACKUP_DEST_DAV_ROOT} ${DAV_BACKUP_DIR_PREFIX}`
PREVIOUS_EVLOG_BACKUP=`get_previous_backup_relative_path ${BACKUP_DEST_EVLOG_ROOT} ${EVLOG_BACKUP_DIR_PREFIX}`

##### Dav/Eventlogデータのプレ同期
#####   MySQLバックアップデータと、Dav/Eventlogの同期タイミングを
#####   可能な限り合わせるために、事前に同期を行い、本番同期の処理時間を
#####   できるだけ短縮するための処理
# WebDavファイルをrsync
outputInfoLog "Dav   backup(pre) start."
exec_file_rsync ${BACKUP_DEST_DAV_ROOT} ${BACKUP_SRC_DAV_ROOT} ${PREVIOUS_DAV_BACKUP}
if [ $? -ne 0 ]; then
  abort 1
fi
outputInfoLog "Dav   backup(pre) end."
# EventLogファイルをrsync
outputInfoLog "EventLog   backup(pre) start."
exec_file_rsync ${BACKUP_DEST_EVLOG_ROOT} ${BACKUP_SRC_EVLOG_ROOT} ${PREVIOUS_EVLOG_BACKUP}
if [ $? -ne 0 ]; then
  abort 1
fi
outputInfoLog "EventLog   backup(pre) end."


# MySQLスレーブサーバのレプリケーションを停止する
mysql_replication_stop


##### Dav/Eventlogデータの本同期

# WebDavファイルをrsync
outputInfoLog "Dav   backup start."
exec_file_rsync ${BACKUP_DEST_DAV_ROOT} ${BACKUP_SRC_DAV_ROOT} ${PREVIOUS_DAV_BACKUP}
if [ $? -ne 0 ]; then
  mysql_replication_start
  abort 1
fi
outputInfoLog "Dav   backup end."

# EventLogファイルをrsync
outputInfoLog "EventLog   backup start."
exec_file_rsync ${BACKUP_DEST_EVLOG_ROOT} ${BACKUP_SRC_EVLOG_ROOT} ${PREVIOUS_EVLOG_BACKUP}
if [ $? -ne 0 ]; then
  mysql_replication_start
  abort 1
fi
outputInfoLog "EventLog   backup end."


##### WebDav/Eventlogバックアップディレクトリの補正
##### セル単位リストアツールでは、UnitUserのバックアップディレクトリがないとエラーになるための対処
DAV_WORK_DIR=${BACKUP_DEST_DAV_ROOT}/dav.backup.tmp
EVLOG_WORK_DIR=${BACKUP_DEST_EVLOG_ROOT}/eventlog.backup.tmp

## MySQLからUnitUserとして使用しているDB一覧を取得する
outputInfoLog "Get DB List start."
DB_LIST=`${MYSQL_CMD} -N -B -e "SHOW DATABASES LIKE '${UNIT_PREFIX}%'" 2>> ${BACKUP_LOG}`
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to SHOW DATABASES."
  mysql_replication_start
  abort 1
fi
outputInfoLog "Get DB List end."

# MySQLのDBは存在するが、WebDav/Eventlogが存在しない
# ユニットユーザに対して空ディレクトリを作成する
outputInfoLog "Check UnitUser data directory start."
check_unituser_data_directory "${DB_LIST}" ${DAV_WORK_DIR}
if [ $? -ne 0 ]; then
  mysql_replication_start
  abort 1
fi
check_unituser_data_directory "${DB_LIST}" ${EVLOG_WORK_DIR}
if [ $? -ne 0 ]; then
  mysql_replication_start
  abort 1
fi
outputInfoLog "Check UnitUser data directory end."


# MySQLスレーブサーバのプロセスを停止する
mysqlstop

# MYSQLバックアップを作成
exec_mysql_backup

if [ $? -ne 0 ]; then
  mysqlstart
  abort 1
fi

# すべてのバックアップが正常終了した場合に、
# 一時バックアップディレクトリを日付されたディレクトリに変名する。
outputInfoLog "Rename temporary backup directory start."

DAV_DST_DIR=${BACKUP_DEST_DAV_ROOT}/dav.${DATE}
EVLOG_DST_DIR=${BACKUP_DEST_EVLOG_ROOT}/eventlog.${DATE}

rename_temporary_backup ${DAV_DST_DIR} ${DAV_WORK_DIR}
RESULT_DAV=${?}
rename_temporary_backup ${EVLOG_DST_DIR} ${EVLOG_WORK_DIR}
RESULT_EVLOG=${?}

if [ "${ARCHIVE_ENABLE}" = "true" ]; then
  rename_temporary_backup ${MYSQL_DST_DIR}.tar.gz ${MYSQL_WORK_DIR}
else
  rename_temporary_backup ${MYSQL_DST_DIR} ${MYSQL_WORK_DIR}
fi

RESULT_MYSQL=${?}

if [ ${RESULT_DAV} -ne 0 -o ${RESULT_EVLOG} -ne 0 -o ${RESULT_MYSQL} -ne 0 ]; then
  mysqlstart
  abort 1
fi
outputInfoLog "Rename temporary backup directory end."

# MySQLスレーブサーバのプロセスを起動する
mysqlstart

# 新バックアップ方式では UnitUser単位の処理は排除された。

outputInfoLog "Start backup file rotation."

# WebDav,イベントログバックアップデータのローテート
remove_backup ${BACKUP_DEST_DAV_ROOT}/ ${DAV_BACKUP_DIR_PREFIX}
remove_backup ${BACKUP_DEST_EVLOG_ROOT}/ ${EVLOG_BACKUP_DIR_PREFIX}

## MySQLバックアップデータのローテート
remove_backup_formysql

outputInfoLog "Finished backup file rotation."


# 二重起動抑止のためにロックを解放
## ロックの解放に失敗した場合は、ログを出力して終了する
releaseLock

outPutScriptEndlog
