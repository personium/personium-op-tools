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
# dc1-commons.sh - 共通関数の定義ファイル
#

# 二重読込チェック
if [ ! -z ${COMMONS_LOADED} ]; then
  # 既に読込済であればすぐに返る。
  return 0
fi

# 読込済フラグを ON
export COMMONS_LOADED=true


STAT_DIR=/fj/var/run

## ---------------
## 処理中止
## ---------------

# 処理中止
# 引数：
# ・終了コード
function abort() {
  outputErrorLog "Failed to restore cell data. Please release the lock file for further operation."
  exit $1
}


# 処理中止（ロックを解放して終了）
# 引数：
# ・終了コード
# ・ロックキー名
function abortWithReleaseLock() {
  if [ -f ${2} ]; then
    releaseLock ${2}
  fi
  outputErrorLog "Failed to restore cell data."
  exit $1
}

## ---------------
## ロック機能
## ---------------

# ロック取得
# 引数：ロックファイルパス
function getLock() {
  if [ -e ${LOCK_PATH} ]; then
    return 1
  fi
  echo $$ > ${LOCK_PATH}
  if [ $? -ne 0 ]; then
    /bin/rm -f ${1} > /dev/null 2>&1
    return 2
  fi
}

# ロック解放
# 引数：ロックファイルパス
function releaseLock() {
  /bin/rm -f ${1}
  if [ $? -ne 0 ]; then
    outputErrorLog "Failed to release lock to prohibit multiple execution."
    /bin/rm -f ${1} > /dev/null 2>&1
    return 1
  fi
}


## ---------------
## ログ出力
## ---------------

# INFOログ出力
# 引数：メッセージ
function outputInfoLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [INFO ] ${1}"
}

# WARNログ出力
# 引数：メッセージ
function outputWarnLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [WARN ] ${1}"
}

# ERRORログ出力
# 引数：メッセージ
function outputErrorLog() {
  echo "`/bin/date +'%Y/%m/%d %H:%M:%S'` [ERROR] ${1}"
}



# UnitUserDB名 (e.g u0_sc-xxx ）を MySQLの生のディレクトリ名(e.g. u0_sc@002dxxx)へ変換する。
# シングルクオートは未対応
function convertUnitUserDBtoRawMySQLName(){
  RESULT=${1}
  RESULT=${RESULT//@/@0040}
  RESULT=${RESULT//\!/@0021}
  RESULT=${RESULT//\"/@0022}
  RESULT=${RESULT//#/@0023}
  RESULT=${RESULT//\$/@0024}
  RESULT=${RESULT//%/@0025}
  RESULT=${RESULT//&/@0026}
#   RESULT=${RESULT//\'/@0027}
  RESULT=${RESULT//(/@0028}
  RESULT=${RESULT//)/@0029}
  RESULT=${RESULT//\*/@002a}
  RESULT=${RESULT//+/@002b}
  RESULT=${RESULT//-/@002d}
  RESULT=${RESULT//./@002e}
  RESULT=${RESULT//:/@003a}
  RESULT=${RESULT//;/@003b}
  RESULT=${RESULT//=/@003d}
  RESULT=${RESULT//\?/@003f}
  RESULT=${RESULT//[/@005b}
  RESULT=${RESULT//]/@005d}
  RESULT=${RESULT//^/@005e}
  RESULT=${RESULT//\`/@0060}
  RESULT=${RESULT//\{/@007b}
  RESULT=${RESULT//|/@007c}
  RESULT=${RESULT//\}/@007d}
  RESULT=${RESULT//\~/@007e}
  echo ${RESULT}
}


# 外部参照宣言
export -f abort
export -f abortWithReleaseLock
export -f getLock
export -f releaseLock
export -f outputInfoLog
export -f outputWarnLog
export -f outputErrorLog
export -f convertUnitUserDBtoRawMySQLName
