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
# dc1-prohibitMultiProcessInvocation.sh - 多重起動チェック
# 引数：
# ・ロックファイルパス
#
# 復帰コード：
# ・0: 正常終了
# ・1: 多重起動
# ・2: ロック失敗

# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

LOCK_PATH=${1}

# 処理開始時メッセージを出力する。
outputInfoLog "Checking multi process invocation."

getLock ${LOCK_PATH}
RET_CODE=${?}
case ${RET_CODE} in
1) outputErrorLog "Multiple instanciation of this program is prohibited. Process aborted."; exit 2;;
2) outputErrorLog "Failed to get process lock. Process aborted."; exit 1 ;;
*) outputInfoLog "No other resotration process is running. Proceeding..."; exit 0;;
esac
exit 0
