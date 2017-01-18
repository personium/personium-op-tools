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
package com.fujitsu.dc.recovery;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fujitsu.dc.common.es.EsIndex;
import com.fujitsu.dc.common.es.impl.EsIndexImpl;
import com.fujitsu.dc.common.es.response.DcBulkResponse;
import com.fujitsu.dc.common.es.response.DcSearchHit;
import com.fujitsu.dc.common.es.response.DcSearchResponse;
import com.fujitsu.dc.common.es.response.EsClientException.EsIndexAlreadyExistsException;
import com.fujitsu.dc.common.es.response.EsClientException.EsIndexMissingException;
import com.fujitsu.dc.recovery.tables.CellTableHandler;
import com.fujitsu.dc.recovery.tables.DavNodeTableHandler;
import com.fujitsu.dc.recovery.tables.EntityTableHandler;
import com.fujitsu.dc.recovery.tables.ITableHandler;
import com.fujitsu.dc.recovery.tables.LinkTableHandler;

/**
 * MySQL -> ElasticSearch リカバリツール.
 */
public class RecoveryManager {

    private static Logger log = LoggerFactory.getLogger(RecoveryManager.class);

    private static final int DEFAULT_EXECUTE_COUNT = 10000;
    private static final int DEFAULT_CHECK_COUNT = 10;

    private static final String[] TABLE_TYPES = {"ENTITY", "CELL", "DAV_NODE", "LINK" };

    private static final ITableHandler[] TABLE_HANDLERS = {new EntityTableHandler(), new CellTableHandler(),
            new DavNodeTableHandler(), new LinkTableHandler() };

    private String esHosts;
    private String esClusetrName;
    private String adsJdbcUrl;
    private String adsUser;
    private String adsPassword;
    private EsRecovery recovery;
    private int executeCnt = DEFAULT_EXECUTE_COUNT;
    private String unitPrefix;
    private int checkCount = DEFAULT_CHECK_COUNT;

    /** index. */
    private String[] indexNames;
    /** clearオプション. */
    private boolean isClear;
    /** リストア後に設定するレプリカ数(-r オプション値). */
    private int replicas;

    /**
     * コンストラクタ.
     */
    public RecoveryManager() {
    }

    /**
     * @param indexName the indexName to set
     */
    public final void setIndexNames(String... indexName) {
        this.indexNames = indexName;
    }

    /**
     * リストア対象のインデックス一覧を取得する.
     * @return リストア対象インデックス一覧、対象インデックスの指定がない場合はnullを返却する
     */
    public final String[] getIndexNames() {
        return this.indexNames;
    }

    /**
     * @param value the isClear to set
     */
    public final void setClear(boolean value) {
        this.isClear = value;
    }

    /**
     * インデックスを削除するかどうかのフラグを返却.
     * @return -c指定時はtrue、それ以外はfalse
     */
    public final boolean isClear() {
        return this.isClear;
    }

    /**
     * @param esHosts the esHosts to set
     */
    public final void setEsHosts(String esHosts) {
        this.esHosts = esHosts;
    }

    /**
     * @param esClusetrName the esClusetrName to set
     */
    public final void setEsClusetrName(String esClusetrName) {
        this.esClusetrName = esClusetrName;
    }

    /**
     * @param adsJdbcUrl the adsJdbcUrl to set
     */
    public final void setAdsJdbcUrl(String adsJdbcUrl) {
        this.adsJdbcUrl = adsJdbcUrl;
    }

    /**
     * @param adsUser the adsUser to set
     */
    public final void setAdsUser(String adsUser) {
        this.adsUser = adsUser;
    }

    /**
     * @param adsPassword the adsPassword to set
     */
    public final void setAdsPassword(String adsPassword) {
        this.adsPassword = adsPassword;
    }

    /**
     * @param executeCnt 1度に処理する件数.
     */
    public final void setExecuteCnt(String executeCnt) {
        if (executeCnt != null && !("".equals(executeCnt))) {
            try {
                this.executeCnt = Integer.valueOf(executeCnt);
            } catch (NumberFormatException e) {
                String format = "configuration parameter value failed(%s), use default value. [%s -> %d]";
                log.warn(String.format(format, Recovery.EXECUTE_COUNT, executeCnt, DEFAULT_EXECUTE_COUNT));
                this.executeCnt = DEFAULT_EXECUTE_COUNT;
            }
        }
    }

    /**
     * バルク登録時のチェックタイミング（何回ごとにチェックするか）を設定する（デフォルト：10回）.
     * @param checkCount バルク登録時のチェックタイミング（何回ごとにチェックするか）.
     */
    public final void setCheckCount(String checkCount) {
        if (checkCount != null && !("".equals(checkCount))) {
            try {
                this.checkCount = Integer.valueOf(checkCount);
            } catch (NumberFormatException e) {
                String format = "configuration parameter value failed(%s), use default value. [%s -> %d]";
                log.warn(String.format(format, Recovery.CHECK_COUNT, checkCount, DEFAULT_CHECK_COUNT));
                this.checkCount = DEFAULT_CHECK_COUNT;
            }
        }
    }

    /**
     * @param unitPrefix Elasticsearchのプレフィックス.
     */
    public final void setUnitPrefix(String unitPrefix) {
        if (unitPrefix != null && !("".equals(unitPrefix))) {
            this.unitPrefix = unitPrefix;
        } else {
            this.unitPrefix = "u0";
        }
    }

    /**
     * インデックスのプレフィックスを取得する.
     * @return インデックスのプレフィックス
     */
    public final String getUnitPrefix() {
        return this.unitPrefix;
    }

    /**
     * -r オプションで指定されたリストア後に設定するレプリカ数を取得する.
     * @return リストア後に設定するレプリカ数
     */
    public int getReplicas() {
        return replicas;
    }

    /**
     * -r オプションで指定されたリストア後に設定するレプリカ数を設定する.
     * @param replicas リストア後に設定するレプリカ数
     */
    public void setReplicas(int replicas) {
        this.replicas = replicas;
    }

    /**
     * リカバリの実行.
     * @throws Exception エラー発生時の例外
     */
    public void recovery() throws Exception {

        // EsRecovery
        try {
            this.recovery = new EsRecovery();
            // this.recovery.setRoutingFlag(this.routingFlag);
            this.recovery.init(esHosts, esClusetrName);
        } catch (Exception e) {
            e.printStackTrace();
            log.error("elasticsearch Connection error");
            throw e;
        }

        if ((null == this.indexNames) || (null == this.indexNames[0])) {
            // インデックスが指定されなかったらマスタのデータベース名を一覧取得
            readDatabaseList();
        }

        log.info(String.format("Elasticsearch Recovery Start. [indexNum=%d]", indexNames.length));

        int count = 0;
        for (String index : this.indexNames) {

            log.info(String.format("%s Recovery Start. [%d/%d]", index, ++count, indexNames.length));

            EsIndex esIndex = null;
            if (index.endsWith(EsIndex.CATEGORY_AD)) {
                esIndex = new EsIndexImpl(index, EsIndex.CATEGORY_AD, 0, 0, this.recovery.getClient());
            } else {
                esIndex = new EsIndexImpl(index, EsIndex.CATEGORY_USR, 0, 0, this.recovery.getClient());
            }
            if (isClear) {
                // インデックス削除
                log.info("Remove index  [" + index + "] Start");
                try {
                    esIndex.delete();
                    log.info("Remove index  [" + index + "] End");
                } catch (EsIndexMissingException e) {
                    log.info("Index [" + index + "] does not exist on elasticsearch");
                } catch (Exception e) {
                    e.printStackTrace();
                    log.error("Failed to delete elasticsearch index");
                    throw e;
                }
            }
            try {
                // インデックス作成
                log.info("Create index  [" + index + "] Start");
                esIndex.create();
                log.info("Create index  [" + index + "] End");
            } catch (Exception e) {
                if (!(e instanceof EsIndexAlreadyExistsException && index.endsWith(EsIndex.CATEGORY_AD))) {
                    e.printStackTrace();
                    log.error("Unable to create a new index [" + index
                            + "]  as the same index already exists on elasticsearch");
                    throw e;
                }
            }
            try {
                // インデックスのレプリカ数を0に設定する
                Map<String, String> settings = new HashMap<String, String>();
                settings.put("index.number_of_replicas", "0");
                esIndex.updateSettings(index, settings);

                // 不要Cellの削除
                log.info("DeleteUnnecessaryCell index  [" + index + "] Start");
                deleteUnnecessaryCell(esIndex);
                log.info("DeleteUnnecessaryCell index  [" + index + "] End");

                // インデックス毎にリカバリ
                log.info("Recovery index  [" + index + "] Start");
                recovery(index);
                log.info("Recovery index  [" + index + "] End");
            } finally {
                // レプリカ数をリストアしたインデックスに設定する
                Map<String, String> settings = new HashMap<String, String>();
                settings.put("index.number_of_replicas", String.valueOf(getReplicas()));
                esIndex.updateSettings(index, settings);
            }

            log.info(String.format("%s Recovery End. [%d/%d]", index, count, indexNames.length));
        }

        log.info("Elasticsearch Recovery End.");
    }

    private void recovery(String index) throws Exception {
        // DataBundle名：u0_ad
        final String dataBundleAdName = this.unitPrefix + "_" + EsIndex.CATEGORY_AD;

        Statement stmt = null;
        Connection con = null;
        ResultSet rs = null;
        ResultSet rsCnt = null;
        int cnt = 0;
        try {
            // JDBC Driver の登録
            Class.forName("com.mysql.jdbc.Driver").newInstance();
        } catch (Exception e) {
            e.printStackTrace();
            log.error("Failed to load JDBC driver");
            throw e;
        }
        // DBへの接続
        con = getMySqlConnection(index);

        try {
            // SQL ステートメント・オブジェクトの作成
            stmt = con.createStatement();
            // SQL ステートメントの発行
            for (int i = 0; i < TABLE_TYPES.length; i++) {
                ITableHandler handler = TABLE_HANDLERS[i];
                rsCnt = stmt.executeQuery(handler.getSelectCountTableSqlString(index, TABLE_TYPES[i]));
                if (rsCnt.next()) {
                    cnt = rsCnt.getInt("CNT");
                }
                List<DcBulkResponse> responseList = new ArrayList<DcBulkResponse>();
                try {
                    // ESへのリストア用テーブルを作成して、データをコピーする。これにより、シーケンス番号が付加されたテーブルとなる。
                    copyTableForRecovery(index, handler, stmt, cnt);

                    // フェッチ件数ごとにリカバリを行う
                    int count = 0;
                    for (int current = 0; current < cnt; current += this.executeCnt) {

                        String sqlstatement = handler.getSelectTableSqlString(index, current + 1, current
                                + this.executeCnt);
                        rs = stmt.executeQuery(sqlstatement);
                        try {
                            DcBulkResponse res = this.recovery.bulk(index, TABLE_TYPES[i], rs, this.unitPrefix);
                            if (res != null) {
                                responseList.add(res); // CELLテーブルへの登録のみの場合、登録データなしの場合はnullが返却される
                            }
                            int regNum = this.recovery.getRestoredCount();

                            // 各テーブル内のレコード件数を出力
                            log.info(String.format("  type : %s [%d/%d]", handler.getCopiedTableName(), current
                                    + regNum, cnt));
                        } catch (Exception e) {
                            // Elasticsearchで例外がスローされた場合は、レスポンスはチェックせずに終了する。
                            e.printStackTrace();
                            log.error("Failed to recover index data [" + index + "] on elasticsearch");
                            throw e;
                        }
                        if (null != rs) {
                            rs.close();
                            rs = null;
                        }
                        // バルク登録の件数（パラメータで設定）ごとにレスポンスをチェックする。
                        if (++count % this.checkCount == 0) {
                            checkBulkResponses(index, responseList);
                        }
                    }
                } finally {
                    // リカバリの完了後、ESへのリストア用テーブルを削除する。
                    dropTable(index, handler, stmt);
                }

                if (null != rsCnt) {
                    rsCnt.close();
                    rsCnt = null;
                }
                // u0_adの場合はCELLテーブルのみリストアして終了する。
                if (TABLE_TYPES[i].equals("CELL") && index.equals(dataBundleAdName)) {
                    cnt = 0;
                }
                cnt = 0;

                // バルク登録の件数（パラメータで設定）ごとにレスポンスをチェックする。
                checkBulkResponses(index, responseList);
            }
            // ESへのリストア完了後、インデックスをリフレッシュする。
            // この際、u0_adは、バルク登録時にリフレッシュ済み。
            if (!index.equals(dataBundleAdName)) {
                this.recovery.refreshIndex(index);
            }
        } catch (SQLException e) {
            e.printStackTrace();
            log.error("Failed to retrieve recovery data from mySQL:  index [" + index + "]");
            throw e;
        } finally {
            try {
                // データベースのクローズ
                if (null != rsCnt) {
                    rsCnt.close();
                    rsCnt = null;
                }
                if (null != rs) {
                    rs.close();
                }
                if (null != stmt) {
                    stmt.close();
                }
                if (null != con) {
                    con.close();
                }
            } catch (SQLException e) {
                e.printStackTrace();
                log.warn("Failed to close mySQL connection");
                throw e;
            }
        }
    }

    /**
     * MySQLへ接続する.
     * @param dbName DB名
     * @return Connection
     * @throws SQLException MySQLへの接続エラー
     */
    private Connection getMySqlConnection(String dbName) throws SQLException {
        Connection connection = null;
        try {
            // データベースへの接続
            connection = DriverManager.getConnection(adsJdbcUrl + "/" + dbName
                    , adsUser
                    , adsPassword);
        } catch (SQLException e) {
            log.error("Failed to connect mySQL:  index [" + dbName + "]");
            throw e;
        }
        return connection;
    }

    /**
     * ESへのリストア用テーブルへデータをコピーする.
     * @param dbName DB名
     * @param handler ESへのリストア用テーブル操作オブジェクト
     * @param stmt SQLステートメント
     * @param cnt リストア対象テーブル内の全レコード件数
     * @throws SQLException SQL実行エラー
     * @throws RecoveryException テーブル間コピー時のレコード件数に不整合がある場合
     */
    private void copyTableForRecovery(final String dbName,
            final ITableHandler handler,
            final Statement stmt,
            final int cnt)
            throws SQLException, RecoveryException {
        // まずはリストア用のESへのリストア用テーブルを作成する。
        stmt.executeUpdate(handler.getCreateTableSqlString(dbName));
        log.info(String.format("create table %s.", handler.getCopiedTableName()));

        // すでにテーブルが作成されている可能性があるため、一旦テーブル内のレコードを削除する。
        stmt.executeUpdate(handler.getTruncateTableSqlString(dbName));
        log.info(String.format("truncate table %s.", handler.getCopiedTableName()));

        // テーブルをコピーする。
        stmt.executeUpdate(handler.getCopyTableSqlString(dbName));
        log.info(String.format("copied table %s.", handler.getCopiedTableName()));

        // コピーしたレコード件数が正しいかどうかを確認する。
        int count = selectCountTable(dbName, handler, stmt);
        if (count != cnt) {
            String message = String.format("failed to copy recoreds. [master=%d, copied=%d]", cnt, count);
            log.error(message);
            throw new RecoveryException(message);
        }
    }

    /**
     * テーブル内の全レコード件数を取得する.
     * @param dbName DB名
     * @param handler ESへのリストア用テーブル操作オブジェクト
     * @param stmt SQLステートメント
     * @return テーブル内の全レコード件数
     * @throws SQLException SQL実行エラー
     */
    private int selectCountTable(final String dbName, final ITableHandler handler, final Statement stmt)
            throws SQLException {
        ResultSet result = stmt.executeQuery(handler.getSelectCountTableSqlString(dbName));
        int count = -1;
        if (result.next()) {
            count = result.getInt("CNT");
        }
        return count;
    }

    /**
     * ESへのリストア用テーブルを削除する.
     * @param dbName DB名
     * @param handler ESへのリストア用テーブル操作オブジェクト
     * @param stmt SQLステートメント
     * @throws SQLException SQL実行エラー
     */
    private void dropTable(final String dbName, final ITableHandler handler, final Statement stmt) throws SQLException {
        stmt.executeUpdate(handler.getDropTableSqlString(dbName));
        log.info(String.format("drop table %s.", handler.getCopiedTableName()));
    }

    /**
     * ESへのバルク登録結果をチェックする.
     * @param index インデックス名
     * @param responseList バルク登録結果のレスポンスリスト
     */
    private void checkBulkResponses(String index, List<DcBulkResponse> responseList) {

        log.info("bulk response check Start.");
        // TODO エラーが発生した際の正式なエラー復帰方法の実装
        // 登録時にエラーが発生している場合は、とりあえずエラーメッセージのみ出力しておく。
        for (DcBulkResponse response : responseList) {
            if (response.hasFailures()) {
                String format = "Failed to recover index data [%s] on elasticsearch. [%s]";
                log.error(String.format(format, index, response.buildFailureMessage()));
            }
        }
        responseList.clear();
        log.info("bulk response check End.");
    }

    /**
     * リカバリ対象のDBかどうかをチェックする.
     * @param databaseName DB名
     * @return リカバリ対象のDBならtrueを返す
     */
    private boolean checkRecoveryTargetDatabase(String databaseName) {
        // ユニットプレフィックスから始まるDBのみリカバリ対象
        if (databaseName.startsWith(this.unitPrefix + "_")) {
            return true;
        }
        return false;
    }

    private void readDatabaseList() throws Exception {

        Statement stmt = null;
        Connection con = null;
        ResultSet rs = null;
        try {
            // JDBC Driver の登録
            Class.forName("com.mysql.jdbc.Driver").newInstance();

            // データベースへの接続
            con = DriverManager.getConnection(adsJdbcUrl + "/", adsUser, adsPassword);

            // SQL ステートメント・オブジェクトの作成
            stmt = con.createStatement();
            // SQL ステートメントの発行
            log.info("=== START database LIST ");
            rs = stmt.executeQuery("SHOW DATABASES");
            ArrayList<String> al = new ArrayList<String>();
            while (rs.next()) {
                String database = rs.getString("Database");
                if (checkRecoveryTargetDatabase(database)) {
                    al.add(database);
                }
            }
            this.indexNames = al.toArray(new String[0]);
            log.info("=== END database LIST " + al.toString());
        } catch (Exception e) {
            e.printStackTrace();
            log.error("Failed to get database list from mySQL");
            throw e;
        } finally {
            try {
                // データベースのクローズ
                if (null != rs) {
                    rs.close();
                }
                if (null != stmt) {
                    stmt.close();
                }
                if (null != con) {
                    con.close();
                }
            } catch (SQLException e) {
                e.printStackTrace();
                log.warn("Failed to close mySQL connection");
                throw e;
            }
        }
    }

    /**
     * 不要なCellの削除.
     * インデックスごとにリストアする場合、U0_adを削除するとリストア対象インデックス以外のCellが削除されてしまう。
     * そのため、u0_adのインデックスは削除せずに、リストア対象インデックスのCellデータのみをここで削除する.
     * @param index 削除対象インデックス
     * @throws Exception Exception
     */
    private void deleteUnnecessaryCell(EsIndex index) throws Exception {
        String indexName = index.getName();
        if (indexName.endsWith(EsIndex.CATEGORY_AD)) {
            return;
        }
        // Cell一覧取得
        String unituseName = indexName.replace(this.unitPrefix + "_", "");
        indexName = this.unitPrefix + "_" + EsIndex.CATEGORY_AD;

        EsIndex esIndex = new EsIndexImpl(indexName, EsIndex.CATEGORY_AD, 0, 0, this.recovery.getClient());
        DcSearchResponse scrollResponse = this.recovery.listCell(esIndex, "Cell", unituseName, 0L);
        Long totalHits = scrollResponse.hits().allPages();
        log.info("Unnecessary Cell Count :[" + totalHits + "]");
        scrollResponse = this.recovery.listCell(esIndex, "Cell", unituseName, totalHits);

        for (DcSearchHit hit : scrollResponse.getHits().getHits()) {
            // 不要CellIDを取得
            String cellId = hit.getId();
            try {
                // Cellの削除
                this.recovery.deleteEntity(esIndex, "Cell", cellId);
            } catch (Exception e) {
                e.printStackTrace();
                log.error("Failed to delete cell data [" + cellId + "] on elasticsearch");
                throw e;
            }
        }
    }
}
