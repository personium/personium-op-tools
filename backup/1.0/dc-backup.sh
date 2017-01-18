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
MYSQL_DST_DIR=${ROOT_DIR}/fj/mysql/data_${DATE}

# Davファイル関連
BACKUP_DAV_FILE=webdavbackup.tar.gz

# イベントログファイル関連
BACKUP_EVLOG_FILE=eventlogbackup.tar.gz

# 処理中止（ロックを開放して終了）
function abort() {
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
  BACKUP_DEST_TAR_DIR=${BACKUP_DEST_DAV_ROOT}
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
  BACKUP_DEST_EVLOG_TAR_DIR=${BACKUP_DEST_EVLOG_ROOT}

  # 読み込んだプロパティファイルからmysqlコマンドを生成
  MYSQL_CMD="/usr/bin/mysql -u ${MYSQL_USER} --password=${MYSQL_PASS} -h ${MYSQL_HOST} --port=${MYSQL_PORT}"
}

# バックアップ先ディレクトリを作成する
function create_directory() {
  # WebDAV用バックアップディレクトリの作成
  if [ ! -d ${BACKUP_DEST_TAR_DIR}/${1} ]; then
    /bin/mkdir -p ${BACKUP_DEST_TAR_DIR}/${1} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to make backup directory. (${BACKUP_DEST_TAR_DIR}/${1})"
      return 1
    fi 
  fi 
  # イベントログ用バックアップディレクトリの作成
  if [ ! -d ${BACKUP_DEST_EVLOG_TAR_DIR}/${1} ]; then
    /bin/mkdir -p ${BACKUP_DEST_EVLOG_TAR_DIR}/${1} >> ${BACKUP_LOG} 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to make backup directory. (${BACKUP_DEST_EVLOG_TAR_DIR}/${1})"
      return 1
    fi 
  fi 
  outputInfoLog "[${UNIT_USER_NAME}] Create backup directory."
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

# MYSQLバックアップ
function exec_mysql_backup() {
  outputInfoLog "MySQL backup start."

  ## mysqlのデータディレクトリの存在チェック
  if [ ! -d ${MYSQL_SRC_DIR} ]; then
    outputErrorLog "No data for backup. path=[${MYSQL_SRC_DIR}]"
    return 1
  fi

  ## mysqlのバックアップ先データディレクトリの存在チェック
  ### 存在した場合は、削除しておく
  if [ -d ${MYSQL_DST_DIR} ]; then
    outputInfoLog "backup directory already exsits. path=[${MYSQL_DST_DIR}]"
    /bin/rm -rf ${MYSQL_DST_DIR} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
      outputErrorLog "Failed to remove backup directory."
    return 1
  fi
  fi

  ## mysqlのデータディレクトリをコピーする
  /bin/cp -pr ${MYSQL_SRC_DIR} ${MYSQL_DST_DIR} >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to backup MySQL data directory. (${MYSQL_SRC_DIR})"
    return 1
    fi 

  outputInfoLog "MySQL backup end."
}

# rsyncを実行し、バックアップ先ディレクトリをバックアップ元と同期する
## ${1}：ファイルのバックアップ先ルートディレクトリ
## ${2}：圧縮後のファイル名
## ${3}：ファイルのバックアップ元ルートディレクトリ
### ディレクトリを再帰的に同期
### パーミッション、グループ、オーナー、タイムスタンプを保持したまま同期
### バックアップ元から削除されたファイルはバックアップ先からも削除する
function exec_file_rsync(){
  outputInfoLog "rsync start. To:${1}"
  pushd ${1} > /dev/null 2>&1

  ## バックアップ対象のルートディレクトリが存在するかのチェック
  if [ ! -d ${3} ]; then
    outputWarnLog "No data for rsync. path=[${3}]"
    return 1
  fi

  /usr/bin/rsync -av --delete --exclude="*/${2}.*" ${3}/ . >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 -a $? -ne 24 ]; then
    ## エラーコード24はバックアップ中にファイル削除が行われた場合に発生する
    ## 削除されたファイルはバックアップする必要がないため、
    ## rsyncの実行結果としては「正常」として扱う
    outputErrorLog "Failed to rsync. To:${1}"
    return 1
  fi
  popd > /dev/null 2>&1
  outputInfoLog "rsync end. To:${1}"
}

# ファイルのバックアップ
## UNIT_USER_NAME：UnitUser名
## ${1}：WebDAVファイルのバックアップ元ルートディレクトリ
## ${2}：WebDAVファイルのバックアップ先ルートディレクトリ
## ${3}：圧縮後のファイル名
function exec_file_backup() {

  pushd ${2} > /dev/null 2>&1

  ## バックアップ対象が存在しない場合は処理を行わない
  if [ ! -d ${1}/${UNIT_USER_NAME} ]; then
    outputInfoLog "No data for backup. Empty backup data will be created.  path=[${2}/${UNIT_USER_NAME}/${3}.${DATE}]"
    ## バックアップデータが存在しない場合であっても、
    ## 他種別のバックアップデータとの整合性を保つために、
    ## 空の tar.gzファイルを作成する。
    ### ダミーファイルの作成
    /bin/touch ${DATE}.dummy > /dev/null 2>&1
    ### 空の tarファイルを作成するための下準備。.gz拡張子無しのファイル名を取得
    TMP_TAR=`echo ${3} | /bin/sed -e "s/.gz$//"`
    ### tarを作成し、その後内容物を削除することで空の tarファイルを作成
    /bin/tar cvf ./${UNIT_USER_NAME}/${TMP_TAR}.${DATE} ${DATE}.dummy > /dev/null 2>&1
    /bin/tar --delete -f ./${UNIT_USER_NAME}/${TMP_TAR}.${DATE} ${DATE}.dummy > /dev/null 2>&1
    ### 圧縮  (foo.tar.${DATE}.gz という名前になる。)
    /bin/gzip ./${UNIT_USER_NAME}/${TMP_TAR}.${DATE} > /dev/null 2>&1
    ### 本来のバックアップファイル名へと改名 ( foo.tar.gz.${DATE} へ改名)
    /bin/mv ./${UNIT_USER_NAME}/${TMP_TAR}.${DATE}.gz ./${UNIT_USER_NAME}/${3}.${DATE} > /dev/null 2>&1
    ### ダミーファイルを削除
    /bin/rm ${DATE}.dummy > /dev/null 2>&1
    return 0
  fi

  ## 作成したWebDavのバックアップをtar.gzに圧縮する
  ## tar.gzファイルが既に存在する場合は上書きする
  outputInfoLog "archive start."

  if [ ! -d ./${UNIT_USER_NAME} ]; then
    /bin/mkdir -p ./${UNIT_USER_NAME} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to create backup directory. path=[${2}/${UNIT_USER_NAME}]"
      return 1
    fi
  fi
  /bin/tar cvfz ./${3}.${DATE} ./${UNIT_USER_NAME} --exclude "./${UNIT_USER_NAME}/${3}.*">> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to archive file."
    return 1
  fi
  # 出力したバックアップファイルを移動
  /bin/mv ./${3}.${DATE} ./${UNIT_USER_NAME}/ >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to move backup directory. (${2}/${3}.${DATE} to ${2}/${UNIT_USER_NAME})"
    /bin/rm -f ./${3}.${DATE}
  fi 
  popd > /dev/null 2>&1
  outputInfoLog "archive end."
}

# 指定されたパスにバックアップファイルを作成する
function store_output_dir_path() {
  outputInfoLog "[${UNIT_USER_NAME}] Create new backup to [${OUTPUT_DIR_PATH}]."
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

# バックアップデータのローテート
# TODO バックアップをSPLITしたときのローテート実装
## ${1}：ユニットユーザのファイルバックアップ先ディレクトリ
## ${2}：バックアップファイル(tar.gz形式)
function remove_backup() {
  if [ ! -d ${1} ]; then
    return;
  fi
  FILE_LIST=`/bin/ls -1t ${1}/${2}.*  2> /dev/null | /bin/egrep "${1}/${2}\.[0-9]{8}$"`
  counter=`expr 1`
  for FILE in ${FILE_LIST}
  do
    if [ $counter -gt ${BACKUP_GENERATION} ]; then
      /bin/rm -f ${FILE} >> ${BACKUP_LOG} 2>&1
      if [ $? -ne 0 ]; then
        outputWarnLog "Failed to remove old backup. (${FILE})"
      fi
    fi
    counter=`expr ${counter} + 1`
  done
}

# MySQLのバックアップデータのローテート
function remove_backup_formysql() {
  DIR_LIST=`/bin/ls -1dt ${MYSQL_SRC_DIR}_* 2>/dev/null | /bin/egrep "${MYSQL_SRC_DIR}_[0-9]{8}$"`
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
  u )
    # 対象ユニットユーザのリスト（CSV形式）
    UNITUSER=`echo $OPTARG | /bin/sed -e 's/,/ /g'`
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
outputInfoLog "Arguments list. -p [${PROPERTIES_FILE_PATH}] -u [${UNITUSER}] -o [${OUTPUT_DIR_PATH}]."
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

# MySQLスレーブサーバのレプリケーションを停止する
mysql_replication_stop
# WebDavファイルをrsync
exec_file_rsync ${BACKUP_DEST_DAV_ROOT} ${BACKUP_DAV_FILE} ${BACKUP_SRC_DAV_ROOT}
# EventLogファイルをrsync
exec_file_rsync ${BACKUP_DEST_EVLOG_ROOT} ${BACKUP_EVLOG_FILE} ${BACKUP_SRC_EVLOG_ROOT}

# MySQLスレーブサーバからUnitUserの一覧を取得する
## 一覧取得に失敗した場合は処理を終了する
## MySQLレプリケーション開始後にDB一覧を取得すると、レプリケーション中断中に新規作成された
## DBが一覧にふくまれてしまい、アーカイブに失敗する。このため、事前にDB一覧を取得する。
## -uオプションで指定されたUnitUser名が存在しない場合は処理を終了する
DB_LIST=`${MYSQL_CMD} -e "SHOW DATABASES;" | /bin/sed -e 's/^ \| //g' 2>> ${BACKUP_LOG}`
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to connect MySQL slave server."
  abort 1
fi
if [ -n "${UNITUSER}" ]; then
  for UNIT_USER_NAME in ${UNITUSER}
  do
    echo ${DB_LIST} | /bin/grep -wqs ${UNIT_USER_NAME}
    if [ $? -ne 0 ]; then
      outputWarnLog "Invalid argument[-u]."
      abort 1
    fi
  done
  DB_LIST=${UNITUSER}
fi

# MySQLスレーブサーバのプロセスを停止する
mysqlstop

# MYSQLバックアップを作成
exec_mysql_backup ${UNIT_USER_NAME} ${UNIT_USER_DB}
if [ $? -ne 0 ]; then
  mysqlstart
  abort 1
fi
# MySQLスレーブサーバのプロセスを起動する
mysqlstart

# UnitUser毎に以下の処理を行う
for UNIT_USER_NAME in ${DB_LIST}
do
  if [[ ! ${UNIT_USER_NAME} =~ ^${UNIT_PREFIX}.* ]]; then
     continue
  fi
  outputInfoLog "[${UNIT_USER_NAME}] UnitUser backup start."

  ##プレフィックスを取る
  UNIT_USER_DB=${UNIT_USER_NAME}
  UNIT_USER_NAME=`echo ${UNIT_USER_NAME} | /bin/sed -e "s/^${UNIT_PREFIX}_//"`

  ## 新規のUnitUserがあればバックアップ先ディレクトリを新規に作成する
  create_directory ${UNIT_USER_NAME}
  if [ $? -ne 0 ]; then
    continue
  fi

  # WebDavバックアップを作成
  outputInfoLog "[${UNIT_USER_NAME}] Dav   backup start."
  exec_file_backup ${BACKUP_SRC_DAV_ROOT} ${BACKUP_DEST_DAV_ROOT} ${BACKUP_DAV_FILE}
  outputInfoLog "[${UNIT_USER_NAME}] Dav   backup end."

  # イベントログバックアップを作成
  outputInfoLog "[${UNIT_USER_NAME}] EventLog   backup start."
  exec_file_backup ${BACKUP_SRC_EVLOG_ROOT} ${BACKUP_DEST_EVLOG_ROOT} ${BACKUP_EVLOG_FILE}
  outputInfoLog "[${UNIT_USER_NAME}] EventLog   backup end."

  # WebDav,イベントログバックアップデータのローテート
  remove_backup ${BACKUP_DEST_TAR_DIR}/${UNIT_USER_NAME} ${BACKUP_DAV_FILE}
  remove_backup ${BACKUP_DEST_EVLOG_TAR_DIR}/${UNIT_USER_NAME} ${BACKUP_EVLOG_FILE}

  outputInfoLog "[${UNIT_USER_NAME}] UnitUser backup end."
done

## MySQLバックアップデータのローテート
remove_backup_formysql

# 二重起動抑止のためにロックを解放
## ロックの解放に失敗した場合は、ログを出力して終了する
releaseLock

outPutScriptEndlog
