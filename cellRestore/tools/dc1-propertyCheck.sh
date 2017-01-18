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
# dc1-propertyCheck.sh - セル単位リストアツールで使用するプロパティの定義内容チェック
# ・定義の有無のみをチェックし、値の妥当性はチェックしない。

. ${TOOL_DIR}/dc1-readPropertyFile.sh

PROPERTIES=( \
'com.fujitsu.dc.core.webdav.basedir' \
'com.fujitsu.dc.core.eventlog.basedir' \
'com.fujitsu.dc.core.backup.mysql.dir' \
'com.fujitsu.dc.core.backup.mysql.prefix' \
'com.fujitsu.dc.core.backup.dav.dir' \
'com.fujitsu.dc.core.backup.dav.prefix' \
'com.fujitsu.dc.core.backup.eventlog.dir' \
'com.fujitsu.dc.core.backup.eventlog.prefix' \
'com.fujitsu.dc.core.mysql.master.host' \
'com.fujitsu.dc.core.mysql.master.port' \
'com.fujitsu.dc.core.mysql.master.user.name' \
'com.fujitsu.dc.core.mysql.master.user.password' \
'com.fujitsu.dc.core.mysql.restore.work.my.conf' \
'com.fujitsu.dc.core.mysql.restore.work.host' \
'com.fujitsu.dc.core.mysql.restore.work.port' \
'com.fujitsu.dc.core.mysql.restore.work.user.name' \
'com.fujitsu.dc.core.mysql.restore.work.user.password' \
'com.fujitsu.dc.core.restore.workspace.mysql.dir' \
'com.fujitsu.dc.core.restore.workspace.webdav.dir' \
'com.fujitsu.dc.core.restore.workspace.eventlog.dir' \
'com.fujitsu.dc.core.es.cluster.name' \
'com.fujitsu.dc.core.es.hosts' \
'com.fujitsu.dc.core.es.unitPrefix' \
'com.fujitsu.dc.core.es.routingFlag' \
'com.fujitsu.dc.core.es.master.host' \
'com.fujitsu.dc.core.restore.memcached.cache.host' \
'com.fujitsu.dc.core.restore.memcached.cache.port' \
)

checkMandatoryProperties ${PROPERTIES[@]}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  exit ${RET_CODE}
fi
