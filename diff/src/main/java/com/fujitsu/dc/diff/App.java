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
package com.fujitsu.dc.diff;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import javax.sql.DataSource;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.GnuParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.dbcp.BasicDataSourceFactory;
import org.apache.commons.dbutils.DbUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fujitsu.dc.common.es.EsClient;
import com.fujitsu.dc.common.es.response.DcIndicesStatusResponse;
import com.fujitsu.dc.common.es.response.DcSearchHit;
import com.fujitsu.dc.common.es.response.DcSearchResponse;
import com.fujitsu.dc.common.es.response.EsClientException;
import com.fujitsu.dc.common.es.util.IndexNameEncoder;
import com.fujitsu.dc.core.model.impl.es.odata.EsQueryHandlerHelper;
import com.fujitsu.dc.diff.LockUtility.AlreadyStartedException;

/**
 * 整合性チェックツール.
 *  | CELL |
 *  | DAV_NODE |
 *  | ENTITY |
 *  | LINK |
 */
public class App {

    private static Logger log = LoggerFactory.getLogger(App.class);
    private static String versionNumber = "";
    private static String unitUser = null;
    private static String clusterName = "elasticsearch";
    private static String clusterHosts = "localhost:9300";
    private static String mysqlHost = "localhost:3306";
    private static String mysqlUser = "root";
    private static String mysqlPassword = "password";
    private static String fetchCount = "1000";
    private static String indexPrefix = "u0";
    private static String binaryFilePath = "/fjnfs/dc-core/dav/";
    private static String excludeFilePath = null;

    private long totalHits = 0L;

    /**
     * Davファイルのチェック状況を保持するクラス.
     */
    private class DavResource extends HashMap<String, Long> {
        private static final long serialVersionUID = 1L;
        private int skipped;

        public DavResource() {
            skipped = 0;
        }

        public int getSkipped() {
            return skipped;
        }

        public void incrementSkipped() {
            this.skipped++;
        }
    }

    /**
     * メインルーチン.
     * @param args オプション
     */
    public static void main(String[] args) {
        loadProperties();
        getParametersAndSetConfig(args);

        log.info(">>>Check started.");
        try {
            if (executableLock()) {
                App app = new App();
                app.execute();
            }
        } finally {
            releaseExecutableLock();
        }
        log.info("<<<Check completed.");
    }

    /**
     * 多重起動抑止のためのロック取得.
     */
    private static boolean executableLock() {
        try {
            LockUtility.lock();
            return true;
        } catch (AlreadyStartedException e) {
            log.info("Already started.");
        } catch (Exception e) {
            log.info("Failed to get lock for the double start control.");
            log.info(e.getMessage(), e);
        }
        return false;
    }

    /**
     * 多重起動抑止のためのロック開放.
     */
    private static void releaseExecutableLock() {
        try {
            LockUtility.release();
        } catch (IOException ex) {
            log.info("Failed to release lock for the double start control");
        }
    }

    private static void loadProperties() {
        Properties properties = new Properties();
        InputStream is = App.class.getClassLoader().getResourceAsStream("dc-diff.properties");
        try {
            properties.load(is);
        } catch (IOException e) {
            throw new RuntimeException("failed to load config!", e);
        } finally {
            try {
                is.close();
            } catch (IOException e) {
                throw new RuntimeException("failed to close config stream", e);
            }
        }
        versionNumber = properties.getProperty("com.fujitsu.dc.diff.version");
    }

    private static void getParametersAndSetConfig(String[] args) {
        Option optUnitUser = new Option("t", "unit-user", true, "ユニットユーザ名");
        Option optClusterName = new Option("c", "cluster-name", true, "Elasticsearchクラスタ名");
        Option optClusterHosts = new Option("h", "cluster-hosts", true, "Elasticsearch接続先ホスト");
        Option optMysqlHost = new Option("m", "mysql-host", true, "MySQLホスト");
        Option optMysqlUser = new Option("u", "mysql-user", true, "MySQLユーザ");
        Option optMysqlPassword = new Option("p", "mysql-password", true, "MySQLパスワード");
        Option optBinaryFilePath = new Option("b", "binary-file-path", true, "バイナリデータディレクトリ");
        Option optExcludeFilePath = new Option("x", "exclude-file-path", true, "除外ディレクトリ");
        Option optIndexPrefix = new Option("f", "index-prefix", true, "インデックスプレフィックス");
        Option optFetchCount = new Option("n", "fetch-count", true, "一度に取得する件数");
        Option optVersion = new Option("v", "version", false, "バージョン情報を表示する");

        Options options = new Options();
        options.addOption(optUnitUser);
        options.addOption(optClusterName);
        options.addOption(optClusterHosts);
        options.addOption(optMysqlHost);
        options.addOption(optMysqlUser);
        options.addOption(optMysqlPassword);
        options.addOption(optIndexPrefix);
        options.addOption(optFetchCount);
        options.addOption(optBinaryFilePath);
        options.addOption(optExcludeFilePath);
        options.addOption(optVersion);
        CommandLineParser parser = new GnuParser();
        CommandLine commandLine;
        try {
            commandLine = parser.parse(options, args, true);
        } catch (ParseException e) {
            (new HelpFormatter()).printHelp("", options);
            log.info("Failed to parse arguments");
            return;
        }
        if (commandLine.hasOption("v")) {
            System.out.println("Version:" + versionNumber);
            System.exit(0);
        }
        if (commandLine.getOptionValue("t") != null) {
            unitUser = commandLine.getOptionValue("t");
        }
        if (commandLine.getOptionValue("c") != null) {
            clusterName = commandLine.getOptionValue("c");
        }
        if (commandLine.getOptionValue("h") != null) {
            clusterHosts = commandLine.getOptionValue("h");
        }
        if (commandLine.getOptionValue("m") != null) {
            mysqlHost = commandLine.getOptionValue("m");
        }
        if (commandLine.getOptionValue("u") != null) {
            mysqlUser = commandLine.getOptionValue("u");
        }
        if (commandLine.getOptionValue("p") != null) {
            mysqlPassword = commandLine.getOptionValue("p");
        }
        if (commandLine.getOptionValue("f") != null) {
            indexPrefix = commandLine.getOptionValue("f");
        }
        if (commandLine.getOptionValue("n") != null) {
            fetchCount = commandLine.getOptionValue("n");
        }

        if (commandLine.getOptionValue("b") != null) {
            binaryFilePath = commandLine.getOptionValue("b");
            if (!binaryFilePath.endsWith("/")) {
                binaryFilePath += "/";
            }
        }
        if (commandLine.getOptionValue("x") != null) {
            excludeFilePath = commandLine.getOptionValue("x");
            if (!excludeFilePath.endsWith("/")) {
                excludeFilePath += "/";
            }
        }
    }

    /**
     * データ整合性をチェックする.
     */
    public void execute() {
        EsClient client = new EsClient(clusterName, clusterHosts);
        Connection conn = getMySqlConnection();

        try {
            List<String> excludeUnitUser = listExcludeUnitUser(indexPrefix, excludeFilePath);
            List<String> indexNames = listEsIndices(client, indexPrefix, unitUser, excludeUnitUser);
            List<String> databases = listMySQLDatabases(conn, indexPrefix, unitUser, excludeUnitUser);

            if (!isIndexAndDatabaseMatched(indexNames, databases)) {
                log.warn("Index and database is not matched.");
                return;
            }

            if (indexNames.isEmpty() && databases.isEmpty()) {
                log.info("UnitUser is nothing");
                return;
            }

            checkMasterConsistency(client, conn, databases);

            clearWorkTable(conn);

            if (unitUser == null && excludeFilePath != null) {
                checkDavResourceConsistency(client, conn, indexNames);
            } else {
                checkDavResourceConsistency(client, conn, indexNames, unitUser);
            }
        } finally {
            DbUtils.closeQuietly(conn);
            client.closeConnection();
        }
    }

    private Connection getMySqlConnection() {
        Connection conn = null;
        Properties mysqlProperties = new Properties();
        mysqlProperties.setProperty("driverClassName", "com.mysql.jdbc.Driver");
        mysqlProperties.setProperty("url", "jdbc:mysql://" + mysqlHost);
        mysqlProperties.setProperty("username", mysqlUser);
        mysqlProperties.setProperty("password", mysqlPassword);
        try {
            DataSource ds = BasicDataSourceFactory.createDataSource(mysqlProperties);
            conn = ds.getConnection();
        } catch (Exception e) {
            log.warn("Faild to connect MySQL");
            log.info(e.getMessage());
        }
        return conn;
    }

    private List<String> listExcludeUnitUser(String prefix, String path) {
        List<String> unitUsers = new ArrayList<String>();
        if (path != null) {
            File dir = new File(path);
            if (!dir.isDirectory()) {
                log.warn("# Not exists directory: " + path);
                return unitUsers;
            }
            File[] files = dir.listFiles();
            for (int i = 0; i < files.length; i++) {
                File file = files[i];
                if (file.getName().startsWith(".")) {
                    continue;
                }
                if (file.isDirectory()) {
                    unitUsers.add(prefix + "_" + file.getName());
                }
            }
        }
        return unitUsers;
    }

    private List<String> listEsIndices(EsClient client,
            String prefix,
            String unitUserName,
            List<String> excludeUnitUser) {
        List<String> indices = new ArrayList<String>();
        DcIndicesStatusResponse statusResponse = client.indicesStatus();
        for (String name : statusResponse.getIndices()) {
            if (unitUserName != null) {
                if (name.equalsIgnoreCase(prefix + "_" + unitUserName)) {
                    indices.add(name);
                    break;
                }
            } else {
                if (name.startsWith(prefix + "_") && !excludeUnitUser.contains(name)) {
                    indices.add(name);
                }
            }
        }
        return indices;
    }

    private List<String> listMySQLDatabases(Connection connection,
            String prefix,
            String unitUserName,
            List<String> excludeUnitUser) {
        List<String> databases = new ArrayList<String>();
        PreparedStatement stmt = null;
        ResultSet resultSet = null;
        try {
            String sql = "show databases";
            stmt = connection.prepareStatement(sql);
            resultSet = stmt.executeQuery();
            while (resultSet.next()) {
                String database = resultSet.getString(1);
                if (unitUserName != null) {
                    if (database.equalsIgnoreCase(prefix + "_" + unitUserName)) {
                        databases.add(database);
                        break;
                    }
                } else {
                    if (database.startsWith(prefix + "_") && !excludeUnitUser.contains(database)) {
                        databases.add(database);
                    }
                }
            }
        } catch (SQLException e) {
            log.warn("Failed to show databases");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(resultSet);
            DbUtils.closeQuietly(stmt);
        }
        return databases;
    }

    private boolean isIndexAndDatabaseMatched(List<String> indices, List<String> databases) {
        List<String> result = compareIndicesAndDatabases(indices, databases);
        if (result.isEmpty()) {
            return true;
        }
        for (String name : result) {
            log.warn("# Not exists index or database: " + name);
        }
        return false;
    }

    private List<String> compareIndicesAndDatabases(List<String> indices, List<String> databases) {
        List<String> result = new ArrayList<String>();
        for (String indexName : indices) {
            if (!(indexPrefix + "_ad").equals(indexName) && !databases.contains(indexName)) {
                result.add(indexName);
            }
        }
        return result;
    }

    private void checkMasterConsistency(EsClient client, Connection conn, List<String> indexNames) {
        for (String name : indexNames) {
            log.info(">>>Checking index [" + name + "] started.");
            checkSingleIndex(client, conn, name);
            log.info("<<<Checking index [" + name + "] completed.");
        }
    }

    private void checkDavResourceConsistency(EsClient client, Connection conn, List<String> indexNames) {
        Map<String, Long> result = new HashMap<String, Long>();
        listWebDavFiles(binaryFilePath, result);
        if (result.isEmpty()) {
            return;
        }
        registToDavWorkTable(conn, result);

        for (String name : indexNames) {
            fetchDavResources(client, conn, name, null);
        }
        checkRecordsMismatchDav(conn);
    }

    private void checkDavResourceConsistency(EsClient client,
            Connection conn,
            List<String> indexNames,
            String unitUserName) {
        for (String name : indexNames) {
            log.info(">>>Checking WebDAV [" + name + "] started.");

            Map<String, Long> result = new HashMap<String, Long>();
            String unitUserDirectoryName = name.substring(name.indexOf("_") + 1);
            String path = binaryFilePath + unitUserDirectoryName;

            listWebDavFiles(path, result);

            File dir = new File(path);
            if (dir.isDirectory()) {
                if (!result.isEmpty()) {
                    registToDavWorkTable(conn, result);
                }

                fetchDavResources(client, conn, name, null);

                checkRecordsMismatchDav(conn);

                clearWorkTable(conn);
            }
            log.info("<<<Checking WebDAV [" + name + "] completed.");
        }
        return;
    }

    private void clearWorkTable(Connection connection) {
        PreparedStatement stmt = null;
        try {
            String sql = "truncate table data_check.CHECK_ES";
            stmt = connection.prepareStatement(sql);
            stmt.executeUpdate();
        } catch (SQLException e) {
            log.warn("Failed to clearWorkTable");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(stmt);
        }

        try {
            String sql = "truncate table data_check.CHECK_FS";
            stmt = connection.prepareStatement(sql);
            stmt.executeUpdate();
        } catch (SQLException e) {
            log.warn("Failed to clearWorkTable");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(stmt);
        }
    }

    private void listWebDavFiles(String path, Map<String, Long> result) {
        File dir = new File(path);
        if (!dir.isDirectory()) {
            log.warn("# Not exists directory: " + path);
            return;
        }
        File[] files = dir.listFiles();
        for (int i = 0; i < files.length; i++) {
            File file = files[i];
            if (file.getName().startsWith(".")) {
                continue;
            }
            if (file.isDirectory()) {
                listWebDavFiles(path + "/" + file.getName(), result);
            }
            if (file.isFile()) {
                String id = file.getName();
                if (!id.endsWith(".deleted")) {
                    result.put(id, 0L);
                }
            }
        }
    }

    private void fetchDavResources(EsClient client, Connection conn, String indexName, String typeName) {
        String scrollId = initializeScrollSearchForDav(client, indexName, typeName);
        log.info("Count of DAV resources: " + totalHits);

        long processed = 0;
        while (true) {
            DavResource esBaseIds = getPageFromElasticsearchForDav(client, scrollId);
            long rowCount = esBaseIds.keySet().size();
            int skipped = esBaseIds.getSkipped();
            log.info("FetchedRecords: " + rowCount + "(skipped:" + skipped + ")");

            if (rowCount == 0 && skipped == 0) {
                break;
            }
            if (rowCount > 0) {
                registToWorkTable(conn, esBaseIds);
            }

            processed += rowCount + skipped;
            log.info("Processed: " + processed + "/" + totalHits);
        }
    }

    private void checkSingleIndex(EsClient client, Connection conn, String indexName) {
        // CELL (Type = 'Cell')
        checkSingleType(client, conn, indexName, "Cell");
        // LINK (Type = 'link')
        checkSingleType(client, conn, indexName, "link");
        // DAV_NODE (Type = 'dav')
        checkSingleType(client, conn, indexName, "dav");
        // ENTITY (Type others)
        checkSingleType(client, conn, indexName, null);
    }

    private void checkSingleType(EsClient client, Connection conn, String indexName, String typeName) {
        String displayTypeName = typeName;
        if (displayTypeName == null) {
            displayTypeName = "Entities";
        }
        log.info(">>>Checking index [" + indexName + ":" + displayTypeName + "] started.");

        clearWorkTable(conn);

        String scrollId;
        if (typeName == "Cell") {
            scrollId = initializeScrollSearchforCell(client, indexName, typeName);
        } else {
            scrollId = initializeScrollSearch(client, indexName, typeName);
        }
        log.info("Count of records: " + totalHits);

        long processed = 0;
        while (true) {
            Map<String, Long> esBaseIds;
            if (typeName == "Cell") {
                esBaseIds = getPageFromElasticsearchForCell(client, scrollId,
                        indexName.substring(indexPrefix.length() + 1));
            } else {
                esBaseIds = getPageFromElasticsearch(client, scrollId);
            }
            long rowCount = esBaseIds.keySet().size();
            log.info("FetchedRecords: " + rowCount);

            if (rowCount == 0) {
                break;
            }

            registToWorkTable(conn, esBaseIds);

            processed += esBaseIds.keySet().size();
            log.info("Processed: " + processed + "/" + totalHits);
        }

        checkRecordsMismatch(conn, indexName, typeName);
        log.info("<<<Checking index [" + indexName + ":" + displayTypeName + "] completed.");
    }

    private String initializeScrollSearchforCell(EsClient client, String indexName, String typeName) {
        String unituserName = indexName.substring(indexPrefix.length() + 1);
        Map<String, Object> query = buildScrollSearchQueryforCell(unituserName);
        DcSearchResponse scrollResponse = client.scrollSearch(indexPrefix + "_ad", typeName, query);
        totalHits = scrollResponse.hits().allPages();
        String scrollId = scrollResponse.getScrollId();
        return scrollId;
    }

    private String initializeScrollSearchForDav(EsClient client, String indexName, String typeName) {
        Map<String, Object> query = buildScrollSearchQueryForDav(typeName);
        DcSearchResponse scrollResponse = client.scrollSearch(indexName, typeName, query);
        totalHits = scrollResponse.hits().allPages();
        String scrollId = scrollResponse.getScrollId();
        return scrollId;
    }

    private Map<String, Object> buildScrollSearchQueryforCell(String unitUserName) {
        Map<String, Object> query = new HashMap<String, Object>();
        query.put("size", Long.parseLong(fetchCount));

        List<String> fields = new ArrayList<String>();
        fields.add("u");
        fields.add("h");
        EsQueryHandlerHelper.composeSourceFilter(query, fields);

        Map<String, Object> filter = new HashMap<String, Object>();
        if (unitUserName.equals("anon")) {
            Map<String, Object> missing = new HashMap<String, Object>();
            missing.put("field", "h.Owner");
            filter.put("missing", missing);
        } else {
            Map<String, Object> term = new HashMap<String, Object>();
            Map<String, Object> wildcardQuery = new HashMap<String, Object>();
            Map<String, Object> wildcard = new HashMap<String, Object>();
            Map<String, Object> queryOwner = new HashMap<String, Object>();
            Map<String, Object> termOwner = new HashMap<String, Object>();
            wildcardQuery.put("query", wildcard);
            wildcard.put("wildcard", queryOwner);
            queryOwner.put("h.Owner.untouched", "*#" + unitUserName);
            List<Map<String, Object>> or = new ArrayList<Map<String, Object>>();
            or.add(wildcardQuery);
            term.put("term", termOwner);
            termOwner.put("h.Owner.untouched", unitUserName);
            or.add(term);
            filter.put("or", or);
        }
        query.put("filter", filter);

        return query;
    }

    private Map<String, Object> buildScrollSearchQueryForDav(String typeName) {
        Map<String, Object> termFilterBodyDav = new HashMap<String, Object>();
        termFilterBodyDav.put("_type", "dav");
        Map<String, Object> termFilterDav = new HashMap<String, Object>();
        termFilterDav.put("term", termFilterBodyDav);
        Map<String, Object> query = new HashMap<String, Object>();
        query.put("filter", termFilterDav);
        query.put("size", Long.parseLong(fetchCount));
        return query;
    }

    private DavResource getPageFromElasticsearchForDav(EsClient client, String scrollId) {
        DavResource result = new DavResource();
        DcSearchResponse scrollResponse = client.scrollSearch(scrollId);
        long num = scrollResponse.hits().hits().length;
        if (num == 0) {
            return result;
        }
        for (DcSearchHit hit : scrollResponse.getHits()) {
            Map<String, Object> source = hit.getSource();
            String davType = (String) source.get("t");
            if (!davType.equals("dav.file")) {
                result.incrementSkipped();
                continue;
            }

            String id = hit.getId();
            result.put(id, 0L);
        }
        return result;
    }

    /*
     * WorkTableに-nで指定された件数ずつ保存する
     */
    private int registToDavWorkTable(Connection connection, Map<String, Long> idMap) {
        long expectedRows = idMap.keySet().size();
        int actualRows = 0;
        long sqlRows = 0;
        Iterator<String> iterator = idMap.keySet().iterator();
        long sqlCount = Long.parseLong(fetchCount);

        for (long count = 0; count < expectedRows; count = count + sqlCount) {
            if (count + sqlCount > expectedRows) {
                // 残り件数がsqlCountより小さい場合_残り件数をsqlRowsに代入
                sqlRows = expectedRows - count;
            } else {
                // 残り件数がsqlCountより大きい場合_sqlCountを代入
                sqlRows = sqlCount;
            }

            StringBuilder sql = new StringBuilder("insert into data_check.CHECK_FS(id, updated) values");
            for (int i = 0; i < sqlRows; i++) {
                if (i > 0) {
                    sql.append(",");
                }
                sql.append("(?,?)");
            }

            PreparedStatement stmt = null;
            try {
                stmt = connection.prepareStatement(sql.toString());
                int index = 1;
                for (int i = 0; i < sqlRows; i++) {
                    String id = iterator.next();
                    stmt.setString(index++, id);
                    stmt.setLong(index++, idMap.get(id));
                }
                actualRows = stmt.executeUpdate();
            } catch (SQLException e) {
                log.warn("Faild to registToWorkTable");
                log.info(e.getMessage());
            } finally {
                DbUtils.closeQuietly(stmt);
            }
        }

        return actualRows;
    }

    /**
     * WebDAVの不整合をチェックする.
     * @param connection MySQLコネクション
     */
    private void checkRecordsMismatchDav(final Connection connection) {
        log.info("[WebDav] checkRecordsMismatchDav start.");
        final String srcTable = "data_check.CHECK_FS";
        final String tmpTable = "data_check.CHECK_ES";
        final String esMissSql =
                "SELECT "
                        + srcTable + ".id," + srcTable + ".updated "
                        + "FROM " + srcTable + " LEFT JOIN " + tmpTable + " USING(id) "
                        + "WHERE " + tmpTable + ".id IS NULL ";
        final String fsMissSql =
                "SELECT "
                        + tmpTable + ".id," + tmpTable + ".updated "
                        + "FROM " + tmpTable + " LEFT JOIN " + srcTable + " USING(id) "
                        + "WHERE " + srcTable + ".id IS NULL ";

        checkRecordsMismatchDavMiss(connection, esMissSql, "DavEsMiss");
        checkRecordsMismatchDavMiss(connection, fsMissSql, "DavFsMiss");
        log.info("[WebDav] checkRecordsMismatchDav completed.");
    }

    /**
     * チェック用の一時テーブルに格納したデータを使用して不整合の有無を確認する.
     * @param connection MySQLコネクション
     * @param sql 不整合検出用のSQL文
     * @paran missType 不整合種別
     */
    private void checkRecordsMismatchDavMiss(final Connection connection, final String sql, final String missType) {
        log.info("[WebDAV] " + missType + " start.");
        PreparedStatement stmt = null;
        ResultSet resultSet = null;
        try {
            stmt = connection.prepareStatement(sql);
            boolean isfailed = false;
            resultSet = stmt.executeQuery();
            while (resultSet.next()) {
                if (!isfailed) {
                    isfailed = true;
                    log.warn("Detected data missing");
                }
                int index = 1;
                String id = resultSet.getString(index++);
                Long updated = resultSet.getLong(index++);
                log.info("[Inconsistency] " + id + "," + updated + ",,," + missType);
            }
        } catch (SQLException e) {
            log.warn("Faild to checkRecordsMismatchDav");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(resultSet);
            DbUtils.closeQuietly(stmt);
        }
        log.info("[WebDAV] " + missType + " completed.");
    }

    private String initializeScrollSearch(EsClient client, String indexName, String typeName) {
        Map<String, Object> query = buildScrollSearchQuery(typeName);
        try {
            DcSearchResponse scrollResponse = client.scrollSearch(indexName, typeName, query);
            totalHits = scrollResponse.hits().allPages();
            String scrollId = scrollResponse.getScrollId();
            return scrollId;
        } catch (EsClientException.EsIndexMissingException e) {
            // ESのIndexがない場合は続行する(Cellしかない場合に当てはまる)
            totalHits = 0;
            log.info(e.getCause().getMessage());
            return null;
        }
    }

    private Map<String, Object> buildScrollSearchQuery(String typeName) {
        Map<String, Object> query = new HashMap<String, Object>();
        query.put("size", Long.parseLong(fetchCount));

        List<String> fields = new ArrayList<String>();
        fields.add("u");
        EsQueryHandlerHelper.composeSourceFilter(query, fields);

        if (typeName == null) {
            List<Map<String, Object>> andFilter = new ArrayList<Map<String, Object>>();

            Map<String, Object> termFilterBodyCell = new HashMap<String, Object>();
            termFilterBodyCell.put("_type", "Cell");
            Map<String, Object> termFilterCell = new HashMap<String, Object>();
            termFilterCell.put("term", termFilterBodyCell);
            Map<String, Object> notFilterCell = new HashMap<String, Object>();
            notFilterCell.put("not", termFilterCell);
            andFilter.add(notFilterCell);

            Map<String, Object> termFilterBodyLink = new HashMap<String, Object>();
            termFilterBodyLink.put("_type", "link");
            Map<String, Object> termFilterLink = new HashMap<String, Object>();
            termFilterLink.put("term", termFilterBodyLink);
            Map<String, Object> notFilterLink = new HashMap<String, Object>();
            notFilterLink.put("not", termFilterLink);
            andFilter.add(notFilterLink);

            Map<String, Object> termFilterBodyDav = new HashMap<String, Object>();
            termFilterBodyDav.put("_type", "dav");
            Map<String, Object> termFilterDav = new HashMap<String, Object>();
            termFilterDav.put("term", termFilterBodyDav);
            Map<String, Object> notFilterDav = new HashMap<String, Object>();
            notFilterDav.put("not", termFilterDav);
            andFilter.add(notFilterDav);

            Map<String, Object> filter = new HashMap<String, Object>();
            filter.put("and", andFilter);
            query.put("filter", filter);
        }

        return query;
    }

    private Map<String, Long> getPageFromElasticsearch(EsClient client, String scrollId) {
        Map<String, Long> result = new HashMap<String, Long>();
        if (scrollId == null) {
            return result;
        }
        DcSearchResponse scrollResponse = client.scrollSearch(scrollId);
        long num = scrollResponse.hits().hits().length;
        if (num == 0) {
            return result;
        }
        for (DcSearchHit hit : scrollResponse.getHits()) {
            String id = hit.getId();
            Object uval = hit.field("u");
            Long updated = 0L;
            if (uval instanceof Integer) {
                updated = new Long((Integer) uval);
            } else {
                updated = (Long) uval;
            }
            result.put(id, updated);
        }
        return result;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Long> getPageFromElasticsearchForCell(EsClient client,
            String scrollId,
            String unitUserName) {
        Map<String, Long> result = new HashMap<String, Long>();
        DcSearchResponse scrollResponse = client.scrollSearch(scrollId);
        long num = scrollResponse.hits().hits().length;
        if (num == 0) {
            return result;
        }
        for (DcSearchHit hit : scrollResponse.getHits()) {
            Map<String, Object> hiddenFields = null;
            Long updated = 0L;

            hiddenFields = (Map<String, Object>) hit.field("h");
            Object uval = hit.field("u");
            if (uval instanceof Integer) {
                updated = new Long((Integer) uval);
            } else {
                updated = (Long) uval;
            }

            String owner = (String) hiddenFields.get("Owner");
            if (owner != null) {
                // encodeEsIndexNameはurlからUnitUser名の部分を取り出す(メソッド内で小文字化される)
                owner = IndexNameEncoder.encodeEsIndexName(owner);
                // unitUserNameはMySQLのデータベース名から作成される(データベース名は小文字になっているはず)
                if (!owner.equals(unitUserName)) {
                    continue;
                }
            }

            String id = hit.getId();
            result.put(id, updated);
        }
        return result;
    }

    private int registToWorkTable(Connection connection, Map<String, Long> idMap) {
        int expectedRows = idMap.keySet().size();
        int actualRows = 0;
        StringBuilder sql = new StringBuilder("insert into data_check.CHECK_ES(id, updated) values");
        for (int i = 0; i < expectedRows; i++) {
            if (i > 0) {
                sql.append(",");
            }
            sql.append("(?,?)");
        }

        PreparedStatement stmt = null;
        try {
            stmt = connection.prepareStatement(sql.toString());
            int index = 1;
            for (String id : idMap.keySet()) {
                stmt.setString(index++, id);
                if (idMap.get(id) == null) {
                    stmt.setLong(index++, Integer.MIN_VALUE);
                } else {
                    stmt.setLong(index++, idMap.get(id));
                }
            }
            actualRows = stmt.executeUpdate();
        } catch (SQLException e) {
            log.warn("Faild to registToWorkTable");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(stmt);
        }
        return actualRows;
    }

    /**
     * 管理データ／ユーザODataの不整合を確認する.
     * @param connection MySQLコネクション
     * @param indexName チェック対象のインデックス名
     * @param tableName チェック対象のテーブル名
     */
    private void checkRecordsMismatch(final Connection connection, final String indexName, final String tableName) {
        log.info("[" + indexName + "] checkRecordsMismatch start.");
        String srcTable = indexName + "." + tableName;
        if (tableName == null) {
            srcTable = "`" + indexName + "`.ENTITY";
        } else {
            if (tableName.equals("Cell")) {
                srcTable = "`" + indexName + "`.CELL";
            }
            if (tableName.equals("dav")) {
                srcTable = "`" + indexName + "`.DAV_NODE";
            }
            if (tableName.equals("link")) {
                srcTable = "`" + indexName + "`.LINK";
            }
        }

        final String tmpTable = "data_check.CHECK_ES";
        final String esMissSql =
                "SELECT "
                        + srcTable + ".id," + srcTable + ".updated "
                        + "FROM " + srcTable + " LEFT JOIN " + tmpTable + " USING(id) "
                        + "WHERE " + tmpTable + ".id IS NULL ";
        final String mySqlMissSql =
                "SELECT "
                        + tmpTable + ".id," + tmpTable + ".updated "
                        + "FROM " + tmpTable + " LEFT JOIN " + srcTable + " USING(id) "
                        + "WHERE " + srcTable + ".id IS NULL ";
        final String timestampMismatchSql =
                "SELECT "
                        + tmpTable + ".id," + tmpTable + ".updated "
                        + "FROM " + srcTable + "," + tmpTable + " "
                        + "WHERE " + srcTable + ".id = " + tmpTable + ".id "
                        + "AND " + srcTable + ".updated != " + tmpTable + ".updated ";

        checkRecordsMismatch(connection, indexName, tableName, srcTable, esMissSql, "EsMiss");
        checkRecordsMismatch(connection, indexName, tableName, srcTable, mySqlMissSql, "MySQLMiss");
        checkRecordsMismatch(connection, indexName, tableName, srcTable, timestampMismatchSql, "TimestampNotMatch");
        log.info("[" + indexName + "] checkRecordsMismatch completed.");
    }

    /**
     * チェック用の一時テーブルに格納したデータを使用して不整合の有無を確認する.
     * @param connection MySQLコネクション
     * @param indexName チェック対象のインデックス名
     * @param tableName チェック対象のテーブル名
     * @param srcTable ログ出力用のテーブル名（DB名＋テーブル名）
     * @param sql 不整合検出用のSQL文
     * @paran missType 不整合種別
     */
    private void checkRecordsMismatch(final Connection connection,
            final String indexName,
            final String tableName,
            final String srcTable,
            final String sql,
            final String missType) {
        log.info("[" + srcTable + "] " + " start.");
        PreparedStatement stmt = null;
        ResultSet resultSet = null;
        try {
            stmt = connection.prepareStatement(sql);
            boolean isfailed = false;
            resultSet = stmt.executeQuery();
            while (resultSet.next()) {
                if (!isfailed) {
                    isfailed = true;
                    log.warn("Detected data missing");
                }
                int index = 1;
                String id = resultSet.getString(index++);
                Long updated = resultSet.getLong(index++);
                log.info("[Inconsistency] " + id + "," + updated + "," + indexName + "," + tableName + "," + missType);
            }
        } catch (SQLException e) {
            log.warn("Faild to checkRecordsMismatch");
            log.info(e.getMessage());
        } finally {
            DbUtils.closeQuietly(resultSet);
            DbUtils.closeQuietly(stmt);
        }
        log.info("[" + srcTable + "] " + " complete.");
    }
}
