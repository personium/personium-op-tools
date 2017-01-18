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
BACKUP_LOG=${ROOT_DIR}/fj/dc-backup/log/dc-backup.log
LOCK_FILE=${ROOT_DIR}/fj/dc-backup/dc-backup.lock

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
function outputScriptEndlog() {
  outputInfoLog "backup end."
  outputInfoLog "------------------------------------------"
}

# プロパティファイルを読む込む
function readProperties() {
  if [ ! -f $1 ]; then
    outputWarnLog "Invalid argument[-p]."
    abort 1
  fi

  # MySQLのユーザID
  MYSQL_USER=`/bin/grep 'com.fujitsu.dc.core.mysql.master.user.name' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ -z ${MYSQL_USER} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.master.user.name' is not defined."
    abort 1
  fi 

  # MySQLのパスワード
  MYSQL_PASS=`/bin/grep 'com.fujitsu.dc.core.mysql.master.user.password' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ -z ${MYSQL_PASS} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.master.user.password' is not defined."
    abort 1
  fi

  # MySQLのホスト
  MYSQL_HOST=`/bin/grep 'com.fujitsu.dc.core.mysql.master.host' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ -z ${MYSQL_HOST} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.master.host' is not defined."
    abort 1
  fi

  # MySQLのポート
  MYSQL_PORT=`/bin/grep 'com.fujitsu.dc.core.mysql.master.port' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ -z ${MYSQL_PORT} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.mysql.master.port' is not defined."
    abort 1
  fi

  # バックアップの世代数
  BACKUP_GENERATION=`/bin/grep 'com.fujitsu.dc.core.backup.count' $1 | /bin/sed -e 's/^.*=//g' | /bin/sed 's/\r//'`
  if [ -z ${BACKUP_GENERATION} ]; then
    outputWarnLog "property 'com.fujitsu.dc.core.backup.count' is not defined."
    abort 1
  fi 

  # 読み込んだプロパティファイルからmysqlコマンドを生成
  MYSQL_CMD="/usr/bin/mysql -u ${MYSQL_USER} --password=${MYSQL_PASS} -h ${MYSQL_HOST} --port=${MYSQL_PORT}"
}

# AWS情報を取得
function getAwsInfo() {
  outputInfoLog "AWS info get start."

  # リージョン
  REGION_ID=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>> ${BACKUP_LOG} | sed "s/[a-z]$//g"`
  outputInfoLog "AWS REGION_ID = [${REGION_ID}]."
  if [ -z ${REGION_ID} ]; then
    outputErrorLog "Failed to get REGION_ID."
    return 1
  fi

  # NFSのインスタンスID
  NFS_INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id 2>> ${BACKUP_LOG}`
  outputInfoLog "AWS NFS_INSTANCE_ID = [${NFS_INSTANCE_ID}]."
  if [ -z ${NFS_INSTANCE_ID} ]; then
    outputErrorLog "Failed to get NFS_INSTANCE_ID."
    return 1
  fi

  # RDSのインスタンスID
  RDS_INSTANCE_ID=`cat /etc/aws/rds_db_instance_identifier 2>> ${BACKUP_LOG}`
  outputInfoLog "AWS RDS_INSTANCE_ID = [${RDS_INSTANCE_ID}]."
  if [ -z ${RDS_INSTANCE_ID} ]; then
    outputErrorLog "Failed to get RDS_INSTANCE_ID."
    return 1
  fi

  # Dav用EBSのIDを取得
  EBS_ID=`/usr/bin/aws ec2 describe-volumes \
    --region ${REGION_ID} \
    --query "Volumes[*].VolumeId" \
    --filter "Name=attachment.instance-id,Values=${NFS_INSTANCE_ID}" \
             "Name=tag:Name,Values=*DataVolume" \
    --output text 2>> ${BACKUP_LOG}`
  outputInfoLog "AWS EBS_ID = [${EBS_ID}]."
  if [ -z ${EBS_ID} ]; then
    outputErrorLog "Failed to get EBS ID."
    return 1
  fi

  outputInfoLog "AWS info get end."
}

# RDSのスナップショットを取得
function getRdsSnapshot() {
  outputInfoLog "RDS snapshot get start."
  # スナップショットのIDリストを取得
  local SNAPSHOTS_IDS=`/usr/bin/aws rds describe-db-snapshots --region ${REGION_ID} --query [DBSnapshots[*].[DBInstanceIdentifier,SnapshotCreateTime,DBSnapshotIdentifier]] --output text  2>> ${BACKUP_LOG}`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to get the list of snapshot in RDS(${RDS_INSTANCE_ID})."
    echo "error"
  else
    outputInfoLog "RDS snapshot get end."
    # 対象インスタンスのSSのみ抽出(現時点ではdescribe-db-snapshotsがfilterをサポートしていないため)＆作成中のSSは除く
    SNAPSHOTS_IDS=`echo "${SNAPSHOTS_IDS}" | grep -i "^${RDS_INSTANCE_ID}\s" | grep -v "None"`
    outputInfoLog "All RDS snapshots >>>"
    echo "${SNAPSHOTS_IDS}" >> ${BACKUP_LOG}
    outputInfoLog "<<<"
    echo "${SNAPSHOTS_IDS}"
  fi
}

# EBSのスナップショットを取得
function getEbsSnapshot() {
  outputInfoLog "EBS snapshot get start."
  local SNAPSHOTS_IDS=`/usr/bin/aws ec2 describe-snapshots --region ${REGION_ID} --query [Snapshots[*].[StartTime,SnapshotId]] --filters Name=volume-id,Values=${EBS_ID} --output text 2>> ${BACKUP_LOG}`
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to get the list of snapshot in EBS(${EBS_ID})."
    echo "error"
  else
    outputInfoLog "EBS snapshot get end."
    # 作成中のSSは除く
    SNAPSHOTS_IDS=`echo "${SNAPSHOTS_IDS}" | grep -v "None"`
    outputInfoLog "All EBS snapshots >>>"
    echo "${SNAPSHOTS_IDS}" >> ${BACKUP_LOG}
    outputInfoLog "<<<"
    echo "${SNAPSHOTS_IDS}"
  fi
}

# EBSバックアップ
function execEbsBackup() {
  outputInfoLog "EBS backup start."

  # EBSのスナップショットを作成する
  /usr/bin/aws ec2 create-snapshot --region ${REGION_ID} --volume-id ${EBS_ID} --description "NFSInstanceId: ${NFS_INSTANCE_ID}" >/dev/null 2>> ${BACKUP_LOG}
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to create EBS(${EBS_ID}) snapshot."
    return 1
  fi

  outputInfoLog "EBS backup end."
}

# 全DBの全テーブルのアンロック
function unlockTables() {
  outputInfoLog "Unlock tables start."
  ${MYSQL_CMD} -e "UNLOCK TABLES;" >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to unlock tables."
    return 1
  fi
  outputInfoLog "Unlock tables end."
}

# RDSバックアップ
function execRdsBackup() {
  outputInfoLog "RDS backup start."

  # テーブルロック
  ## DB一覧を取得
  DATABASES=$(${MYSQL_CMD} -e "show databases" -B -N 2>> ${BACKUP_LOG})
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to show databases. (${DATABASES})"
    return 1
  fi
  ## システム系のDBはロックできないため除外
  DATABASES=`echo ${DATABASES} | sed -e 's/\.*information_schema\.*//g' | sed -e 's/\.*performance_schema\.*//g' | sed -e 's/\.*mysql\.*//g'`
  outputInfoLog "Lock Databases = [${DATABASES}]."

  ## ロック用のクエリ作成
  LOCK_QUERY="LOCK TABLES "
  for DATABASE_NAME in ${DATABASES}
  do
    ### テーブル一覧を取得
    TABLES=$(${MYSQL_CMD} ${DATABASE_NAME} -e "show tables" -B -N 2>> ${BACKUP_LOG})
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to show tables. (${TABLES})"
      return 1
    fi
    for TABLE_NAME in ${TABLES}
    do
      LOCK_QUERY="${LOCK_QUERY}\`${DATABASE_NAME}\`.${TABLE_NAME} WRITE, "
    done
  done
  LOCK_QUERY=`echo ${LOCK_QUERY} | sed -e 's/,$/;/g'`

  ## ロック(全テーブル同時に実施)
  outputInfoLog "Lock Databases start."
  ${MYSQL_CMD} -e "${LOCK_QUERY}" >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to lock tables."
    return 1
  fi
  outputInfoLog "Lock Databases end."

  # FLUSH
  outputInfoLog "Flush Databases start."
  ${MYSQL_CMD} -e "FLUSH TABLES;" >> ${BACKUP_LOG} 2>&1
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to flush tables."
    return 1
  fi
  outputInfoLog "Flush Databases end."

  # RDSのスナップショットを作成する
  outputInfoLog "Create RDS shanpshots start."
  /usr/bin/aws rds create-db-snapshot --region ${REGION_ID} --db-snapshot-identifier ${RDS_INSTANCE_ID}-"`/bin/date +'%Y%m%d%H%M%S'`" --db-instance-identifier ${RDS_INSTANCE_ID} >/dev/null 2>> ${BACKUP_LOG}
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to create RDS(${RDS_INSTANCE_ID}) snapshot."
    return 1
  fi
  outputInfoLog "Create RDS shanpshots end."

  # アンロック
  unlockTables

  outputInfoLog "RDS backup end."
}

# EBSバックアップデータのローテート
function rotateEbsBackup() {
  outputInfoLog "EBS rotate start."

  # 世代数を超えた分のスナップショットIDリストを取得
  EBS_SNAPSHOTS_IDS=`getEbsSnapshot`
  if [ "${EBS_SNAPSHOTS_IDS}" = "error" ]; then
    return 1
  fi
  DEL_EBS_SNAPSHOTS_IDS=`echo "${EBS_SNAPSHOTS_IDS}" | sort -r | awk -v bg="${BACKUP_GENERATION}" 'NR > bg { print $2; }'`
  outputInfoLog "Delete EBS snapshots >>>"
  echo "${DEL_EBS_SNAPSHOTS_IDS}" >> ${BACKUP_LOG}
  outputInfoLog "<<<"

  # スナップショットを削除
  for DEL_SNAPSHOTS_ID in ${DEL_EBS_SNAPSHOTS_IDS}
  do
    outputInfoLog "Delete EBS snapshot = [${DEL_SNAPSHOTS_ID}] start."
    /usr/bin/aws ec2 delete-snapshot --region ${REGION_ID} --snapshot-id ${DEL_SNAPSHOTS_ID} >/dev/null 2>> ${BACKUP_LOG}
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to delete the snapshot(${DEL_SNAPSHOTS_ID}) of EBS(${EBS_ID})."
      return 1
    fi
    outputInfoLog "Delete EBS snapshot = [${DEL_SNAPSHOTS_ID}] end."
  done

  outputInfoLog "EBS rotate end."
}

# RDSバックアップデータのローテート
function rotateRdsBackup() {
  outputInfoLog "RDS rotate start."

  # 世代数を超えた分のスナップショットIDリストを取得
  RDS_SNAPSHOTS_IDS=`getRdsSnapshot`
  if [ "${RDS_SNAPSHOTS_IDS}" = "error" ]; then
    return 1
  fi
  DEL_RDS_SNAPSHOTS_IDS=`echo "${RDS_SNAPSHOTS_IDS}" | sort -r | awk -v bg="${BACKUP_GENERATION}" 'NR > bg { print $3; }'`
  outputInfoLog "Delete RDS snapshots ----- >>>"
  echo "${DEL_RDS_SNAPSHOTS_IDS}" >> ${BACKUP_LOG}
  outputInfoLog "<<<"

  # スナップショットを削除
  for DEL_RDS_SNAPSHOTS_ID in ${DEL_RDS_SNAPSHOTS_IDS}
  do
    outputInfoLog "Delete RDS snapshot = [${DEL_RDS_SNAPSHOTS_ID}] start."
    /usr/bin/aws rds delete-db-snapshot --region ${REGION_ID} --db-snapshot-identifier ${DEL_RDS_SNAPSHOTS_ID} >/dev/null 2>> ${BACKUP_LOG}
    if [ $? -ne 0 ]; then
      outputErrorLog "Failed to delete the snapshot(${DEL_RDS_SNAPSHOTS_ID}) of RDS(${RDS_INSTANCE_ID})."
      return 1
    fi
    outputInfoLog "Delete RDS snapshot = [${DEL_RDS_SNAPSHOTS_ID}] end."
  done

  outputInfoLog "RDS rotate end."
}

#### メイン処理 #####
outputInfoLog "backup start."

# パラメータのパースを実施する
while getopts ":p:" ARGS
do
  case $ARGS in
  p )
    # プロパティファイルのパス
    PROPERTIES_FILE_PATH=$OPTARG
    ;;
  :)
    outputWarnLog "[-$OPTARG] requires an argument."
    outputScriptEndlog
    exit 1
    ;;
  esac
done

# -p パラメタは必須
outputInfoLog "Arguments list. -p [${PROPERTIES_FILE_PATH}]."
if [ -z "${PROPERTIES_FILE_PATH}" ]; then
  outputWarnLog "[-p] arguments is necessary."
  outputScriptEndlog
  exit 1
fi

# ロックファイルが存在するか確認し、存在しない場合は作成する
## ロックファイルが存在する場合、ログを出力し終了する
if [ -f ${LOCK_FILE} ]; then
  outputInfoLog "backup has already started."
  outputScriptEndlog
  exit 0
fi
echo $$ > ${LOCK_FILE}

# -pオプションで渡されたdc-config.propertiesファイルから必要なプロパティを読み込む
readProperties ${PROPERTIES_FILE_PATH}

# AWSから必要な情報を取得
getAwsInfo
if [ $? -ne 0 ]; then
  outputScriptEndlog
  abort 1
fi

# バックアップ作成前のバックアップ数を取得
## RDS
RDS_SS_LIST_BEFORE=`getRdsSnapshot`
if [ "${RDS_SS_LIST_BEFORE}" = "error" ]; then
  return 1
elif [ -z "${RDS_SS_LIST_BEFORE}" ]; then
  # 初回バックアップ時
  RDS_SS_NUM_BEFORE=0
else
  RDS_SS_NUM_BEFORE=`echo "${RDS_SS_LIST_BEFORE}" | wc -l`
fi
## EBS
EBS_SS_LIST_BEFORE=`getEbsSnapshot`
if [ "${EBS_SS_LIST_BEFORE}" = "error" ]; then
  return 1
elif [ -z "${EBS_SS_LIST_BEFORE}" ]; then
  # 初回バックアップ時
  EBS_SS_NUM_BEFORE=0
else
  EBS_SS_NUM_BEFORE=`echo "${EBS_SS_LIST_BEFORE}" | wc -l`
fi

# RDSバックアップを作成
execRdsBackup
if [ $? -ne 0 ]; then
  # アンロック
  unlockTables
  outputScriptEndlog
  abort 1
fi

# EBSバックアップ作成
execEbsBackup
if [ $? -ne 0 ]; then
  outputScriptEndlog
  abort 1
fi

# バックアップの作成待ち(世代数＋１のバックアップが作成されてしまわないための策)
# 300秒待ち合わせても、RDSのバックアップ完了までに間に合わない恐れがあるが、
# 次のバックアップ時に世代数を超えた分は削除されるため、300秒を超えては待たないものとする
for i in `seq 1 16`; do
  # バックアップ作成後のバックアップ数を取得
  ## RDS
  RDS_SS_LIST_AFTER=`getRdsSnapshot`
  if [ "${RDS_SS_LIST_AFTER}" = "error" ]; then
    return 1
  elif [ -z "${RDS_SS_LIST_AFTER}" ]; then
    # 初回バックアップ時
    RDS_SS_NUM_AFTER=0
  else
    RDS_SS_NUM_AFTER=`echo "${RDS_SS_LIST_AFTER}" | wc -l`
  fi
  ## EBS
  EBS_SS_LIST_AFTER=`getEbsSnapshot`
  if [ "${EBS_SS_LIST_AFTER}" = "error" ]; then
    return 1
  elif [ -z "${EBS_SS_LIST_AFTER}" ]; then
    # 初回バックアップ時
    EBS_SS_NUM_AFTER=0
  else
    EBS_SS_NUM_AFTER=`echo "${EBS_SS_LIST_AFTER}" | wc -l`
  fi

  # 作成できたのであれば抜ける
  if [ ${RDS_SS_NUM_BEFORE} -lt ${RDS_SS_NUM_AFTER} -a ${EBS_SS_NUM_BEFORE} -lt ${EBS_SS_NUM_AFTER} ]; then
    outputInfoLog "Snapshot create completed."
    break
  # 15min待っても作成が完了しなかった場合にはエラーログを出して先に進む
  elif [ ${i} -eq 16 ]; then
    if [ ${RDS_SS_NUM_BEFORE} -eq ${RDS_SS_NUM_AFTER} ]; then
      outputErrorLog "Timed out to confirm the completion of RDS(${RDS_INSTANCE_ID}) snapshot creating."
    fi
    if [ ${EBS_SS_NUM_BEFORE} -eq ${EBS_SS_NUM_AFTER} ]; then
      outputErrorLog "Timed out to confirm the completion of EBS(${EBS_ID}) snapshot creating."
    fi
    break
  fi
  # スリープ
  sleep 1m
done

# EBSバックアップデータのローテート
rotateEbsBackup
if [ $? -ne 0 ]; then
  outputScriptEndlog
  abort 1
fi

# RDSバックアップデータのローテート
rotateRdsBackup
if [ $? -ne 0 ]; then
  outputScriptEndlog
  abort 1
fi

# 二重起動抑止のためにロックを解放
## ロックの解放に失敗した場合は、ログを出力して終了する
releaseLock

outputScriptEndlog
