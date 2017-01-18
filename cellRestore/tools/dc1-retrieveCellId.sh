#!/bin/bash
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
# リストア元MySQLから指定されたCell名のCell IDを検索する。
#

# =======================================================================
#  本 shellスクリプトは、結果として CellIDを文字列として返します。
#  ログを標準出力に書き出すと、この動作が変わってしまうため、
#  Infoログ等の利用は、絶対禁止です。
# =======================================================================

_UNIT_USER_NAME=$1
_CELL_NAME=$2

# プロパティファイルの読み込み
. ${TOOL_DIR}/dc1-readPropertyFile.sh


_UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`

#
# リストア元MySQL情報
#

_SOURCE_MYSQL_HOST=`getProp "com.fujitsu.dc.core.mysql.restore.work.host"`
_SOURCE_MYSQL_PORT=`getProp "com.fujitsu.dc.core.mysql.restore.work.port"`
_SOURCE_MYSQL_USER=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.name"`
_SOURCE_MYSQL_PASSWORD=`getProp "com.fujitsu.dc.core.mysql.restore.work.user.password"`
_SOURCE_MYSQL_DATABASE="${_UNIT_PREFIX}_${_UNIT_USER_NAME}"

#
# 共通設定
#

# リストア対象情報
_MYSQL_HOME="/usr/"

# ツール動作情報
_MYSQL_OPTION="--host=${_SOURCE_MYSQL_HOST} --port=${_SOURCE_MYSQL_PORT} --user=${_SOURCE_MYSQL_USER} --password=${_SOURCE_MYSQL_PASSWORD} ${_SOURCE_MYSQL_DATABASE}"

# Cell IDを検索
if [ ! -n "${_CELL_ID}" ]; then
  "${_MYSQL_HOME}/bin/mysql" ${_MYSQL_OPTION} --skip-column-names -e "select id from CELL where declared_properties like '%\"Name\":\"${_CELL_NAME}\"%'" > ./cell_count 2> /dev/null
  _CELL_COUNT=`cat ./cell_count | wc -l`
  if [ ${_CELL_COUNT} -ne 1 ]; then
    echo "Failed to retrieve cell id. cell name: [${_CELL_NAME}], cell count: [${_CELL_COUNT}] Process aborted."
    exit 1
  fi
  _CELL_ID=`head -1 ./cell_count`
fi
rm -f ./cell_count

echo ${_CELL_ID}

exit 0
