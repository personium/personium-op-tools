#coding: UTF-8

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
# 指定されたCellに紐付くデータをElasticsearchから取得する
#
# 引数
#   esMasterHost：Elasticsearchのホスト名（ポートつき）
#      例）10.123.120.145:9200
#   unitPrefix：対象とするIndexのプレフィックス
#      例）u0
#   unitUserName：対象とするUnitUser
#      例）vet
#   cellId：対象とするセルのID
#   outputFilePath：Elasticsearchから取得した結果の出力先ファイルパス

import os
import sys
try:
  import simplejson as json
except ImportError:
  import json
import urllib
import httplib
import datetime


PROGRESS_COUNT = 1000

def outputInfoLog(message):
  d=datetime.datetime.today()
  print "%s [INFO ] %s" % (d.strftime("%Y/%m/%d %H:%M:%S"), message)

def outputWarnLog(message):
  d=datetime.datetime.today()
  print "%s [WARN ] %s" % (d.strftime("%Y/%m/%d %H:%M:%S"), message)

def outputErrorLog(message):
  d=datetime.datetime.today()
  print "%s [ERROR] %s" % (d.strftime("%Y/%m/%d %H:%M:%S"), message)

def initScrollSearch(_esMasterHost, _esIndex, _cellId) :
  params = '{"query":{"term":{"c":{"value":"' + _cellId + '"}}},"fields":["_id","_type","u"]}'
  headers = {"Content-type": "application/x-www-form-urlencoded","Accept": "apllication/json"}
  connection = httplib.HTTPConnection(_esMasterHost)
  connection.request("POST", "/%s/_search?search_type=scan&scroll=5m&size=5000" % (_esIndex), params, headers)
  response = connection.getresponse()
  data = response.read()
  connection.close()
  loadedJson = json.loads(data)
  return {"scroll_id":loadedJson["_scroll_id"], "total_hits":loadedJson["hits"]["total"]}

def scrollSearch(_esMasterHost, scrollId) :
  connection = httplib.HTTPConnection(_esMasterHost)
  connection.request("POST", "/_search/scroll?scroll=5m&scroll_id=%s" % scrollId)
  response = connection.getresponse()
  data = response.read()
  connection.close()
  loadedJson = json.loads(data)
  return {"scroll_id":loadedJson["_scroll_id"], "hits":loadedJson["hits"]["hits"]}

def writeIdList(_file, _hit) :
  source = _hit["fields"]
  if isinstance(source["u"],list):
    # ES1.2ではfieldsの値が配列になっているため、配列の要素を取り出すようにしている。
    update  = source["u"][0]
  else:
    update  = source["u"]
  _file.write("\"u\":%d,\"_id\":\"%s\",\"_type\":\"%s\"\n" % (update, _hit["_id"], _hit["_type"]))

#
# main.
#

# 引数チェック
if len(sys.argv) != 6:
  outputErrorLog("Usage: dc1-invokeDiffValidation.sh <ES-master-host> <unit-prefix> <unit-user-name> <cell-id> <output-file>")
  sys.exit(1)

esMasterHost = sys.argv[1]
unitPrefix=sys.argv[2]
unitUserName=sys.argv[3]
cellId = sys.argv[4]
outputFilePath = sys.argv[5]

esIndex = "%s_%s" % (unitPrefix, unitUserName)

# scroll searchのための初期化
try:
  initResponse = initScrollSearch(esMasterHost, esIndex, cellId)
  scrollId = initResponse["scroll_id"]
  totalHits = initResponse["total_hits"]

except Exception as e:
  outputErrorLog("Failed to access to Elasticsearch. type:[%s] %s" % (str(type(e)), str(e)))
  sys.exit(1)

# 検索結果出力用のファイルオープン
file = None
try:
  file = open(outputFilePath, "w")

  processedCount = 0

  while True:
    scrollResponse = scrollSearch(esMasterHost, scrollId)
    scrollId = scrollResponse["scroll_id"]
    hits = scrollResponse["hits"]

    if len(hits) == 0 :
      break;

    for hit in hits :
      writeIdList(file, hit)

      processedCount += 1
      if processedCount % PROGRESS_COUNT == 0:
        outputInfoLog("Processing records %d of %d" % (processedCount, totalHits))

  if processedCount % PROGRESS_COUNT != 0:
    outputInfoLog("Process completed. Total records: %d" % (processedCount))

except Exception as e:
  outputErrorLog("Failed to search from Elasticsearch. type:[%s] %s" % (str(type(e)), str(e)))
  sys.exit(1)

finally:
  if file:
    # 検索結果出力用のファイルクローズ
    file.close()


sys.exit(0)
