/**
 * Personium
 * Copyright 2016 FUJITSU LIMITED
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.fujitsu.dc.recovery.tables;

/**
 * ESへのリストア用LINKテーブルを操作するためのDDL／DMLを定義するインターフェース.
 */
public class LinkTableHandler extends AbstractTableHandler {

    /**
     * リカバリ用一時テーブル名を取得する.
     * @return リカバリ用一時テーブル名
     */
    @Override
    public String getCopiedTableName() {
        return "LINK_COPIED";
    }

    /**
     * テーブル作成用DDLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル作成用DDL
     */
    @Override
    public String getCreateTableSqlString(String dbName) {
        String sqlFormat = "CREATE  TABLE IF NOT EXISTS `%s`.`LINK_COPIED` ("
                + "`seq` bigint not null auto_increment ,"
                + "`id` VARCHAR(81) BINARY NOT NULL ,"
                + "`cell_id` VARCHAR(40) NULL ,"
                + "`box_id` VARCHAR(40) NULL ,"
                + "`node_id` VARCHAR(40) NULL ,"
                + "`ent1_type` VARCHAR(200) NOT NULL ,"
                + "`ent1_id` VARCHAR(40) NOT NULL ,"
                + "`ent2_type` VARCHAR(200) NOT NULL ,"
                + "`ent2_id` VARCHAR(40) NOT NULL ,"
                + "`updated` BIGINT UNSIGNED NULL ,"
                + "`published` BIGINT UNSIGNED NULL ,"
                + "PRIMARY KEY (`seq`, `id`)"
                + ") ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 MAX_ROWS=4294967295";
        return String.format(sqlFormat, dbName);
    }

    /**
     * テーブル間コピー用DMLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル間コピー用DML
     */
    @Override
    public String getCopyTableSqlString(String dbName) {
        String sqlFormat = "INSERT INTO `%1$s`.`LINK_COPIED`"
                + " SELECT NULL,id,cell_id,box_id,node_id,ent1_type,"
                + "ent1_id,ent2_type,ent2_id,updated,published FROM `%1$s`.`LINK`";
        return String.format(sqlFormat, dbName);
    }
}
