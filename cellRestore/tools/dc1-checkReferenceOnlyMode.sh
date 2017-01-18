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


_UNIT_USER=$1

# プロパティファイル読込
. ${TOOL_DIR}/dc1-readPropertyFile.sh

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

# プロパティ値取得
_MEMCACHED_HOST_FOR_LOCK_KEY="com.fujitsu.dc.core.cache.memcached.host"
_MEMCACHED_PORT_FOR_LOCK_KEY="com.fujitsu.dc.core.cache.memcached.port"
_UNIT_PREFIX_KEY="com.fujitsu.dc.core.es.unitPrefix"

_MEMCACHED_HOST_FOR_LOCK=`getProp ${_MEMCACHED_HOST_FOR_LOCK_KEY}`
_MEMCACHED_PORT_FOR_LOCK=`getProp ${_MEMCACHED_PORT_FOR_LOCK_KEY}`
_UNIT_PREFIX=`getProp ${_UNIT_PREFIX_KEY}`

# telnetコマンド
_TELNET="telnet ${_MEMCACHED_HOST_FOR_LOCK} ${_MEMCACHED_PORT_FOR_LOCK}"

# 実行結果は一時ファイルに書き込む。※ 標準出力では結果が正常に取得できない。
_STDOUT=`pwd`/checkReferenceOnlyMode.stdout
_STDERR=`pwd`/checkReferenceOnlyMode.stderr

_SLEEP_PERIOD=5


#
# メイン
#
outputInfoLog "Start checking ReferenceOnly mode for [${_UNIT_USER}]."

#
# 必須パラメータの存在チェック
#
if [ $# -ne 1 ]; then
  outputErrorLog "Number of parameters is wrong. Process aborted."
  exit 1
fi

#
# プロパティファイル中の必須プロパティ存在チェック
#
mandatoryPropKeys=( ${_MEMCACHED_HOST_FOR_LOCK_KEY} ${_MEMCACHED_PORT_FOR_LOCK_KEY} ${_UNIT_PREFIX_KEY})
checkMandatoryProperties ${mandatoryPropKeys[@]}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
#   エラーログは出力済
    exit 1
fi

function checkReferenceOnlyMode() {

  _KEY=$1
  _TARGET=$2

  _CHECK_CMD="get ${_KEY}"
  ( sleep ${_SLEEP_PERIOD}; echo "${_CHECK_CMD}"; sleep ${_SLEEP_PERIOD}; echo "quit" ) | ${_TELNET} > ${_STDOUT} 2> ${_STDERR}

  #
  # 接続確認を行う。 "Connected to xxxxx" を引っかける。
  #
  RESULT_OF_CONNECTION=`sed -e "2p" -e"d" ${_STDOUT} | grep 'Connected to' | wc -l`

  # 結果が1行存在すること
  if [ ${RESULT_OF_CONNECTION} != 1 ]; then
  #   エラー： 接続できなかった.
      outputErrorLog "Failed to connect to memcached server. Process aborted."
      exit 1
  fi

  #
  # ReferenceOnlyモードチェックの結果確認。"Escape character is～"の行から"END"までに出力が無いこと
  #
  _RESULT_LINE_COUNT=`sed -e "/^Escape character is/,/^END/p" -e"d"  ${_STDOUT} | wc -l`

  if [ ${_RESULT_LINE_COUNT} != 2 ]; then
  #   エラー。期待される結果ではなかった。
      outputErrorLog "${_TARGET} is in reference only mode. Check the log file [${_STDOUT}]. Process aborted."
      exit 1
  fi
}

#
# PCS全体のReferenceOnlyモードのチェック
#
# UnLock状態：
#   get ReferenceOnly-
#   END
# Lock状態
#   get ReferenceOnly-
#   VALUE ReferenceOnly- 0 114
#   {"explantion":"Could not create JdbcAds","sql":"","threadId":"qtp13214581-20","created":1393467579089,"unitId":""}
#   END
#
checkReferenceOnlyMode "ReferenceOnly-" "PCS"

# UnitUser単位のReferenceOnlyモードの場合
# UnLock状態：
#   get ReferenceOnly-${_UNIT_PREFIX}_${_UNIT_USER}
#   END
# Lock状態
#   get ReferenceOnly-${_UNIT_PREFIX}_${_UNIT_USER}
#   VALUE ReferenceOnly-${_UNIT_PREFIX}_${_UNIT_USER} 0 471
#   {"explantion":"UpDateCount is 0","sql":"com.mysql.jdbc.JDBC4PreparedStatement@1356640: update `${_UNIT_PREFIX}_${_UNIT_USER}`.CELL set   type='Cell',   cell #_id=null,   box_id=null,   node_id=null,   declared_properties='{\"Name\":\"cellName\"}',   dynamic_properties='{}',   hidden_proper t#ies='{}',   links='{}',   acl='{}',   published=1393467783108,   updated=1393467853800 where id='LdG_ST2ATWmf_aYtHDgxnw'","threadId":"qt p3#96920-15","created":1393467854735,"unitId":"${_UNIT_PREFIX}_${_UNIT_USER}"}
#   END
checkReferenceOnlyMode "ReferenceOnly-${_UNIT_PREFIX}_${_UNIT_USER}" "Target UnitUser"

# 処理成功のログを出力する。
outputInfoLog "Checking ReferenceOnly mode for [${_UNIT_USER}] is completed. Proceeding..."

exit 0

