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

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.json.simple.parser.JSONParser;
import org.json.simple.parser.ParseException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fujitsu.dc.common.es.EsBulkRequest;
import com.fujitsu.dc.common.es.EsIndex;
import com.fujitsu.dc.common.es.EsType;
import com.fujitsu.dc.common.es.impl.EsIndexImpl;
import com.fujitsu.dc.common.es.impl.EsTypeImpl;
import com.fujitsu.dc.common.es.impl.InternalEsClient;
import com.fujitsu.dc.common.es.response.DcBulkResponse;
import com.fujitsu.dc.common.es.response.DcRefreshResponse;
import com.fujitsu.dc.common.es.response.DcSearchResponse;
import com.fujitsu.dc.core.model.impl.es.odata.EsQueryHandlerHelper;

/**
 * ElasticSearchへBulkによるリカバリを行う.
 */
public class EsRecovery {

    private static Logger log = LoggerFactory.getLogger(EsRecovery.class);

    /** ESクライアント. */
    InternalEsClient client;

    JSONParser parser = new JSONParser();

    /** バルク登録した件数. */
    private int restoredCount = 0;

    /**
     * ES接続等の初期処理を行う.
     * @param hosts ESのホスト名
     * @param cluster クラスタ名
     */
    public void init(String hosts, String cluster) {
        this.client = InternalEsClient.getInstance(cluster, hosts);
    }

    /**
     * @return the client
     */
    public final InternalEsClient getClient() {
        return client;
    }

    /**
     * AbstractEsBulkRequest.
     */
    abstract class AbstractEsBulkRequest implements EsBulkRequest {
        String type = "";
        HashMap<String, Object> map;
        String id = "";
        String cellId = "";

        public AbstractEsBulkRequest(String t) {
        }

        public BULK_REQUEST_TYPE getRequestType() {
            return BULK_REQUEST_TYPE.INDEX;
        }

        public String getId() {
            return id;
        }

        public String getType() {
            return type;
        }

        public String getCellId() {
            return cellId;
        }

        public Map<String, Object> getSource() {
            return this.map;
        }

        @SuppressWarnings("unchecked")
        protected HashMap<String, Object> jsonParse(String str) {
            try {
                if (null == str) {
                    return null;
                } else {
                    return (HashMap<String, Object>) parser.parse(str);
                }
            } catch (ParseException e) {
                log.warn("ERROR DATA:[" + str + "]");
                e.printStackTrace();
                return null;
            } catch (Throwable e) {
                log.warn("ERROR DATA:[" + str + "]");
                e.printStackTrace();
                return null;
            }
        }
    }

    /**
     * EsBulkCell.
     */
    class EsBulkCell extends AbstractEsBulkRequest {

        public EsBulkCell(String t) {
            super(t);
        }

        public void setSource(ResultSet rs) {
            this.map = new HashMap<String, Object>();
            try {
                this.type = "Cell";
                this.id = rs.getString("id");
                map.put("u", rs.getLong("updated"));
                map.put("b", rs.getString("box_id"));
                map.put("c", rs.getString("cell_id"));
                map.put("p", rs.getLong("published"));
                map.put("n", rs.getString("node_id"));
                map.put("l", jsonParse(rs.getString("links")));
                map.put("a", jsonParse(rs.getString("acl")));
                map.put("d", jsonParse(rs.getString("dynamic_properties")));
                map.put("s", jsonParse(rs.getString("declared_properties")));
                map.put("h", jsonParse(rs.getString("hidden_properties")));
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * EsBulkLink.
     */
    class EsBulkLink extends AbstractEsBulkRequest {

        public EsBulkLink(String t) {
            super(t);
        }

        public void setSource(ResultSet rs) {
            this.map = new HashMap<String, Object>();
            try {
                this.type = "link";
                this.id = rs.getString("id");
                this.cellId = rs.getString("cell_id");
                map.put("t2", rs.getString("ent2_type"));
                map.put("u", rs.getLong("updated"));
                map.put("b", rs.getString("box_id"));
                map.put("t1", rs.getString("ent1_type"));
                map.put("c", rs.getString("cell_id"));
                map.put("p", rs.getLong("published"));
                map.put("k1", rs.getString("ent1_id"));
                map.put("k2", rs.getString("ent2_id"));
                map.put("n", rs.getString("node_id"));
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * EsBulkDav.
     */
    class EsBulkDav extends AbstractEsBulkRequest {

        public EsBulkDav(String t) {
            super(t);
        }

        public void setSource(ResultSet rs) {
            this.map = new HashMap<String, Object>();
            try {
                this.type = "dav";
                this.id = rs.getString("id");
                this.cellId = rs.getString("cell_id");
                map.put("c", rs.getString("cell_id"));
                map.put("b", rs.getString("box_id"));
                map.put("t", rs.getString("node_type"));
                map.put("s", rs.getString("parent_id"));
                map.put("p", rs.getLong("published"));
                map.put("u", rs.getLong("updated"));
                map.put("o", jsonParse(rs.getString("children")));
                map.put("a", jsonParse(rs.getString("acl")));
                map.put("d", jsonParse(rs.getString("properties")));
                map.put("f", jsonParse(rs.getString("file")));
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * EsBulkEntity.
     */
    class EsBulkEntity extends AbstractEsBulkRequest {

        public EsBulkEntity(String t) {
            super(t);
        }

        public void setSource(ResultSet rs) {
            this.map = new HashMap<String, Object>();
            try {
                this.type = rs.getString("type");
                this.id = rs.getString("id");
                this.cellId = rs.getString("cell_id");
                map.put("c", rs.getString("cell_id"));
                map.put("b", rs.getString("box_id"));
                map.put("n", rs.getString("node_id"));
                map.put("t", rs.getString("entity_id"));
                map.put("p", rs.getLong("published"));
                map.put("u", rs.getLong("updated"));
                map.put("s", jsonParse(rs.getString("declared_properties")));
                map.put("d", jsonParse(rs.getString("dynamic_properties")));
                map.put("h", jsonParse(rs.getString("hidden_properties")));
                if (this.type.equals("UserData")) {
                    String str = rs.getString("links");
                    // MySQLには["~","~",...] という形式で格納されているため、
                    // ブラケットとダブルクォーテーションを取り除く
                    str = trimBracket(str);

                    String[] array = str.split(",");
                    List<String> links = new ArrayList<String>();
                    for (String link : array) {
                        link = link.trim();
                        link = trimDoubleQuotation(link);
                        if (!link.isEmpty()) {
                            links.add(link);
                        }
                    }
                    map.put("l", links);
                } else {
                    map.put("l", jsonParse(rs.getString("links")));
                }
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }

        protected String trimBracket(String str) {
            str = str.replace("[", "");
            str = str.replace("]", "");
            return str;
        }

        protected String trimDoubleQuotation(String str) {
            str = str.replace("\"", "");
            return str;
        }
    }

    /**
     * Bulk登録を行う.
     * @param index 対象Index
     * @param tableType 対象Type
     * @param data 登録するデータ(ResultSetの配列)
     * @param unitPrefix ESのプレフィックス
     * @return Bulk登録のレスポンス
     */
    public DcBulkResponse bulk(String index, String tableType, ResultSet data, String unitPrefix) {
        this.restoredCount = 0;
        ArrayList<EsBulkRequest> cellList = new ArrayList<EsBulkRequest>();
        Map<String, List<EsBulkRequest>> bulkMap = new HashMap<String, List<EsBulkRequest>>();
        DcBulkResponse bulkRequest = null;
        try {
            while (data.next()) {
                if ("cell".equals(tableType.toLowerCase())) {
                    if (!index.equals(unitPrefix + "_" + EsIndex.CATEGORY_AD)) {
                        EsBulkCell bulk = new EsBulkCell(tableType);
                        bulk.setSource(data);
                        cellList.add(bulk);
                    }
                } else if ("link".equals(tableType.toLowerCase())) {
                    EsBulkLink bulk = new EsBulkLink(tableType);
                    bulk.setSource(data);

                    // セルID毎にリストを作成する
                    String routingId = bulk.getCellId();
                    List<EsBulkRequest> list;
                    if (bulkMap.containsKey(routingId)) {
                        list = bulkMap.get(routingId);
                    } else {
                        list = new ArrayList<EsBulkRequest>();
                        bulkMap.put(routingId, list);
                    }
                    list.add(bulk);
                } else if ("dav_node".equals(tableType.toLowerCase())) {
                    EsBulkDav bulk = new EsBulkDav(tableType);
                    bulk.setSource(data);

                    // セルID毎にリストを作成する
                    String routingId = bulk.getCellId();
                    List<EsBulkRequest> list;
                    if (bulkMap.containsKey(routingId)) {
                        list = bulkMap.get(routingId);
                    } else {
                        list = new ArrayList<EsBulkRequest>();
                        bulkMap.put(routingId, list);
                    }
                    list.add(bulk);
                } else {
                    EsBulkEntity bulk = new EsBulkEntity(tableType);
                    bulk.setSource(data);

                    // セルID毎にリストを作成する
                    String routingId = bulk.getCellId();
                    if ("domain".equals(bulk.getType().toLowerCase())) {
                        routingId = EsIndex.CELL_ROUTING_KEY_NAME;
                    }

                    List<EsBulkRequest> list;
                    if (bulkMap.containsKey(routingId)) {
                        list = bulkMap.get(routingId);
                    } else {
                        list = new ArrayList<EsBulkRequest>();
                        bulkMap.put(routingId, list);
                    }
                    list.add(bulk);
                }
                this.restoredCount++;
            }
            if (cellList.size() > 0) {
                client.bulkRequest(unitPrefix + "_ad", EsIndex.CELL_ROUTING_KEY_NAME, cellList, false);
            }

            if (bulkMap.size() > 0) {
                bulkRequest = client.asyncBulkCreate(index, bulkMap);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return bulkRequest;
    }

    /**
     * Elasticsearchのインデックスを作成する.
     * @param indexNmae インデックス名
     * @param category カテゴリ
     */
    public void createEsIndex(String indexNmae, String category) {
        (new EsIndexImpl(indexNmae, category, 0, 0, client)).create();
    }

    /**
     * Elasticsearchのインデックスをリフレッシュする.
     * @param index インデックス名
     */
    public void refreshIndex(String index) {
        DcRefreshResponse res = client.refresh(index);
        log.info("refresh success shards = " + res.getSuccessfulShards());
        log.info("refresh failed  shards = " + res.getFailedShards());
    }

    /**
     * Cellの一覧取得.
     * @param index 取得対象インデックス
     * @param typeName 取得対象タイプ名
     * @param unituseName 取得対象ユニットユーザ名
     * @param size 取得件数
     * @return 検索結果
     */
    public DcSearchResponse listCell(EsIndex index, String typeName, String unituseName, long size) {
        Map<String, Object> query = buildScrollSearchQueryforCell(unituseName, size);
        EsType type = new EsTypeImpl(index.getName(), typeName, null, 0, 0, client);
        DcSearchResponse scrollResponse = type.search(query);
        return scrollResponse;
    }

    /**
     * Cell一覧取得用クエリの作成.
     * @param unitUserName ユニットユーザ名
     * @param size 取得件数
     * @return 生成したクエリ
     */
    private Map<String, Object> buildScrollSearchQueryforCell(String unitUserName, long size) {
        Map<String, Object> query = new HashMap<String, Object>();
        query.put("size", size);

        List<String> fields = new ArrayList<String>();
        fields.add("u");
        fields.add("h");
        // ESのバージョンに合わせたクエリの作成
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

    /**
     * Entityの削除.
     * @param index 削除対象インデックス
     * @param typeName 削除対象タイプ名
     * @param id 削除対象ドキュメントID
     */
    public void deleteEntity(EsIndex index, String typeName, String id) {
        EsType type = new EsTypeImpl(index.getName(), typeName, EsIndex.CELL_ROUTING_KEY_NAME, 0, 0, client);
        type.delete(id);
    }

    /**
     * バルク登録した件数を取得する.
     * @return the processingCount
     */
    public int getRestoredCount() {
        return restoredCount;
    }

}
