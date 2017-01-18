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

outputInfoLog "Start clearing memcached."


# 利用するプロパティ
_MEMCACHED_HOST="com.fujitsu.dc.core.restore.memcached.cache.host"
_MEMCACHED_PORT="com.fujitsu.dc.core.restore.memcached.cache.port"

# プロパティファイル中の必須プロパティ存在チェック
mandatoryPropKeys=( ${_MEMCACHED_HOST} ${_MEMCACHED_PORT})
checkMandatoryProperties ${mandatoryPropKeys[@]}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
#   エラーログは出力済
    exit 1
fi


# プロパティ値取得
_MEMCACHED_HOST_FOR_CACHE=`getProp ${_MEMCACHED_HOST}`
_MEMCACHED_PORT_FOR_CACHE=`getProp ${_MEMCACHED_PORT}`

# telnetコマンド
_TELNET="telnet ${_MEMCACHED_HOST_FOR_CACHE} ${_MEMCACHED_PORT_FOR_CACHE}"

# 実行結果は一時ファイルに書き込む。※ 標準出力では結果が正常に取得できない。
_STDOUT=`pwd`/clearMemcache.stdout
_STDERR=`pwd`/clearMemcache.stderr

_SLEEP_PERIOD=5

# Memcached のクリアを実行。
( sleep 5; echo 'flush_all'; sleep 5; echo 'quit' ) | ${_TELNET} > ${_STDOUT} 2> ${_STDERR}


# 接続確認を行う。 "Connected to xxxxx" を引っかける。
RESULT_OF_CONNECTION=`sed -e "2p" -e"d" ${_STDOUT} | grep 'Connected to' | wc -l`

# 結果が1行存在すること
if [ ${RESULT_OF_CONNECTION} != 1 ]; then
#   エラー： 接続できなかった.
    outputErrorLog "Failed to connect to memcached server. Process aborted."
    exit 1
fi


# flush_allの結果確認。最後の行が OKであること。
LAST_LINE=`tail -1 ${_STDOUT}`

if [ $LAST_LINE != "OK" ]; then
#   エラー。期待される結果ではなかった。
    outputErrorLog "Failed to clear memcached data. Check the log file [${_STDOUT}]. Process aborted."
    exit 1
fi

# 処理成功のログを出力する。
outputInfoLog "Cleared the memcached for data cache. Proceeding..."

exit 0

