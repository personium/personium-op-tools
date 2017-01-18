#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# personium
# Copyright 2014 FUJITSU LIMITED
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
# Retrieve nubmer of replica on Elasticsearch.
#
# Arguments
#  - Host name or address of Elasticsearch
#  - HTTP listener port of Elasticsearch
#  - Version of Elasticsearch

import os
import sys
import json
import urllib
import httplib

if __name__ == "__main__":

  if (len(sys.argv) != 4):
    print "Invalid arguments: \"%s\"" % (sys.argv)
    quit()
  
  es_host = sys.argv[1]
  es_port = sys.argv[2]
  es_version = sys.argv[3]

  connection = httplib.HTTPConnection("%s:%s" % (es_host, es_port))
  connection.request( "GET", "/_settings")
  response = connection.getresponse()
  data = response.read()
  connection.close()
  json = json.loads(data)

  if (es_version == "0.19.9"):
    # example:
    #{
    #  "u0_ad": {
    #      "settings": {
    #          "index.analysis.analyzer.default.type": "cjk",
    #          "index.number_of_replicas": "1",
    #          "index.number_of_shards": "10",
    #          "index.version.created": "190999"
    #      }
    #  }, ...

    for (key, value) in json.iteritems():
      print "%s:%s" % (key, value['settings']['index.number_of_replicas'])

  else:
    # example:
    #{
    #    "u0_ad": {
    #      "settings": {
    #          "index": {
    #              "analysis": {
    #                  "analyzer": {
    #                      "default": {
    #                          "type": "cjk"
    #                      }
    #                  }
    #              }, 
    #              "number_of_replicas": "1",
    #              "number_of_shards": "10",
    #              "uuid": "RJopekkRRI6O6YM5Wre89A",
    #              "version": {
    #                  "created": "1020199"
    #              }
    #          }
    #      }
    #  }, ...

    for (key, value) in json.iteritems():
      print "%s:%s" % (key, value['settings']['index']['number_of_replicas'])

