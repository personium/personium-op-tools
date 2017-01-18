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


# cell_sweep.sh(セル一括削除_MySQL)を実行する

# 終了コード：
#   0: 正常終了
#   1: 既に起動している
#   2: エラー終了


# 共通関数定義ファイル読み込み
. ${TOOL_DIR}/dc1-commons.sh

outputInfoLog "Cell sweep started."

CELL_SWEEP_DIR=/fj/dc1-cell-sweeper

# ロックファイルが存在するか確認し、存在しない場合は作成する
## このシェルスクリプトは、cell sweepのロックが存在しない前提として実行する
## ロックファイルが存在する場合、ログを出力し異常終了とする
ROOT_DIR=
LOCK_FILE=${ROOT_DIR}${CELL_SWEEP_DIR}/dc1-cell-sweeper.lock
if [ -f ${LOCK_FILE} ]; then
  outputErrorLog "Cell sweep process has already been started."
  exit 1
fi

# Cell sweep呼出し
${CELL_SWEEP_DIR}/cell_sweep.sh -p ${CONF_PATH}
if [ $? -ne 0 ]; then
  outputErrorLog "Failed to sweep target cell in PCS. (Cause: see. ${CELL_SWEEP_DIR}/log/dc1-cell-sweeper.log) Process aborted."
  exit 2
fi

outputInfoLog "Target cell is successfully sweeped from PCS. Proceeding..."
exit 0
