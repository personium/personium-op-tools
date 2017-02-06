#!/bin/sh
#
# Personium
# Copyright 2016 - 2017 FUJITSU LIMITED
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
# personium-propertyCheck.sh - セル単位リストアツールで使用するプロパティの定義内容チェック
# ・定義の有無のみをチェックし、値の妥当性はチェックしない。

. ${TOOL_DIR}/personium-readPropertyFile.sh

PROPERTIES=( \
'io.personium.core.webdav.basedir' \
'io.personium.core.eventlog.basedir' \
'io.personium.core.backup.mysql.dir' \
'io.personium.core.backup.mysql.prefix' \
'io.personium.core.backup.dav.dir' \
'io.personium.core.backup.dav.prefix' \
'io.personium.core.backup.eventlog.dir' \
'io.personium.core.backup.eventlog.prefix' \
'io.personium.core.mysql.master.host' \
'io.personium.core.mysql.master.port' \
'io.personium.core.mysql.master.user.name' \
'io.personium.core.mysql.master.user.password' \
'io.personium.core.mysql.restore.work.my.conf' \
'io.personium.core.mysql.restore.work.host' \
'io.personium.core.mysql.restore.work.port' \
'io.personium.core.mysql.restore.work.user.name' \
'io.personium.core.mysql.restore.work.user.password' \
'io.personium.core.restore.workspace.mysql.dir' \
'io.personium.core.restore.workspace.webdav.dir' \
'io.personium.core.restore.workspace.eventlog.dir' \
'io.personium.core.es.cluster.name' \
'io.personium.core.es.hosts' \
'io.personium.core.es.unitPrefix' \
'io.personium.core.es.routingFlag' \
'io.personium.core.es.master.host' \
'io.personium.core.restore.memcached.cache.host' \
'io.personium.core.restore.memcached.cache.port' \
)

checkMandatoryProperties ${PROPERTIES[@]}
RET_CODE=${?}
if [ ${RET_CODE} -ne 0 ]; then
  exit ${RET_CODE}
fi
