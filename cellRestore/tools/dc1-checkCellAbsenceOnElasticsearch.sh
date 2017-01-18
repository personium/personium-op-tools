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
# パラメタで指定された名前のCellの情報がElasticsearchに存在するかどうかを返す
#  $1 セル名
# 終了コード：
#   0: セル情報が存在しない
#   1: セル情報が存在する
#   2: Elasticsearchへの検索が失敗した
#

_CELL_NAME=$1

. ${TOOL_DIR}/dc1-commons.sh
# プロパティファイルの読み込み
. ${TOOL_DIR}/dc1-readPropertyFile.sh

_UNIT_PREFIX=`getProp "com.fujitsu.dc.core.es.unitPrefix"`

#
# リストア先Elasticsearch情報
#
_TARGET_ES_HOST=`getProp "com.fujitsu.dc.core.es.master.host"`
_TARGET_ES_INDEX="${_UNIT_PREFIX}_ad"


#
# セル名で検索
#

outputInfoLog "Checking the cell absence in Elasticsearch. [${_CELL_NAME}]."

_COUNT=`curl -s -XGET "http://${_TARGET_ES_HOST}/${_TARGET_ES_INDEX}/Cell/_search?q=s.Name.untouched:${_CELL_NAME}&size=0&routing=pcsCell" |  python -c 'import sys,json;data=json.loads(sys.stdin.read()); print data["hits"]["total"]' 2> /dev/null`
if [ $? -ne 0 ]; then
  outputErrorLog "Unable to collect cell status in PCS. Process aborted."
  exit 2
fi

if [ ${_COUNT} -ne 0 ]; then
  outputErrorLog "Target cell still exists in PCS. Process aborted."
  exit 1
fi

outputInfoLog "Absence of target cell in Elasticseach is confirmed. Proceeding..."
exit 0


