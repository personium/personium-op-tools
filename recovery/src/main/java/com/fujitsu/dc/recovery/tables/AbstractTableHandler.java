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
 * ESへのリストア用LINKテーブルを操作するためのDDL／DMLを定義する抽象クラス.
 */
public abstract class AbstractTableHandler implements ITableHandler {

    /**
     * リカバリ用一時テーブル名を取得する.
     * @return リカバリ用一時テーブル名
     */
    public abstract String getCopiedTableName();

    /**
     * テーブル作成用DDLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル作成用DDL
     */
    public abstract String getCreateTableSqlString(String dbName);

    /**
     * テーブル間コピー用DMLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル間コピー用DML
     */
    public abstract String getCopyTableSqlString(String dbName);

    /**
     * テーブル内の全レコード削除用DMLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル内の全レコード削除用DML
     */
    public String getTruncateTableSqlString(String dbName) {
        String sqlFormat = "TRUNCATE TABLE `%s`.`%s`";
        return String.format(sqlFormat, dbName, getCopiedTableName());
    }

    /**
     * テーブル削除用DMLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル削除用DML
     */
    public String getDropTableSqlString(String dbName) {
        String sqlFormat = "DROP TABLE IF EXISTS `%s`.`%s`";
        return String.format(sqlFormat, dbName, getCopiedTableName());
    }

    /**
     * テーブル内の全レコード件数取得用DMLを取得する.
     * @param dbName DB名
     * @return 生成したテーブル内の全レコード件数取得用DML
     */
    public String getSelectCountTableSqlString(String dbName) {
        return getSelectCountTableSqlString(dbName, getCopiedTableName());
    }

    /**
     * テーブル内の全レコード件数取得用DMLを取得する.
     * @param dbName DB名
     * @param tableName テーブル名
     * @return 生成したテーブル内の全レコード件数取得用DML
     */
    public String getSelectCountTableSqlString(String dbName, String tableName) {
        String sqlFormat = "SELECT COUNT(*) AS CNT FROM `%s`.`%s`";
        return String.format(sqlFormat, dbName, tableName);
    }

    /**
     * テーブル内のレコード取得用DMLを取得する.
     * @param dbName DB名
     * @param start 開始位置
     * @param end 終了位置
     * @return 生成したテーブル内のレコード取得用DML
     */
    public String getSelectTableSqlString(String dbName, int start, int end) {
        String sqlFormat = "SELECT * FROM `%s`.`%s` WHERE seq BETWEEN %d AND %d";
        return String.format(sqlFormat, dbName, getCopiedTableName(), start, end);
    }

}
