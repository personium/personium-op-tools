# personium-op-tools

## About

Tools for production operations of Personium server system.

## Components

```
ads-cell-sweeper       - A batch program to delete the cells that are marked to be deleted.
backup                 - A batch program for ADS server backup.
cellRestore            - A tools for cell-level restore from backup data.
costom-errorpage       - Costomization program of Tomcat's errorpage.
diff                   - A shell command to check differeces between elasticesearch and ADS(MySQL)
esgclog                - A batch program print GC log from elasticesearch.
logback-settings       - A shell command to run logback as a daemon process.
mx-diskusage           - A shell command to run personium-mx.
recovery               - Data recovery program from ADS to elasticesearch.
```


## License

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Copyright 2016 FUJITSU LIMITED
```