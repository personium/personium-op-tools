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
# dc1-readPropertyFile.sh - 引数で渡されたプロパティファイルを読み込む
# ・先頭に '#' を記述した行をコメント行とみなす。
#
# 復帰コード：
# ・0 正常終了
# ・1 異常終了（パラメータ誤り）
# ・2 異常終了


# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

if [ -z "${CONF_PATH}" ]; then
  outputErrorLog "Configuration file path is not defined."
  exit 1
fi

## プロパティファイル存在チェック
if [ ! -f "${CONF_PATH}" ]; then
  outputErrorLog "Configuration file '${CONF_PATH}' cannot be found or cannot be read. "
  exit 2
fi

## プロパティファイル読み込み
## ・空行、コメント行をスキップする。
declare -A properties
IFS=$'\n'
for line in `/bin/grep -v "^\s*#" ${CONF_PATH} | grep '='`
do
  K=`echo $line | sed -e "s/\s*=.*$//"`
  V=`echo $line | sed -e "s/^.*=\s*//"`
  properties[$K]=$V
done
IFS=$' \t\n' 


## プロパティ値の取得
## 引数：プロパティ名
function getProp() {
  echo ${properties[$1]}
}


## プロパティの未定義チェック
## 引数：プロパティ名の配列
## 復帰コード：
## ・0 すべてのプロパティが定義されている
## ・1 一部のプロパティが定義されていない
function checkMandatoryProperties() {
  local returnValue=0
  for target in ${@}
  do
  local val=`getProp "${target}"`

  if [ -z "${val}" ]; then 
    outputErrorLog "Mandatory property '${target}' is not specified in configuration file '/fj/dc-config.properties'".
    returnValue=1
  fi      
  done
  return ${returnValue}
}

# 外部参照宣言
export -f getProp
export -f checkMandatoryProperties
