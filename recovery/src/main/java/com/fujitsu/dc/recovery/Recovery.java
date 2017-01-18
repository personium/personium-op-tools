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

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Properties;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.GnuParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fujitsu.dc.common.es.EsIndex;
import com.fujitsu.dc.recovery.LockUtility.AlreadyStartedException;

/**
 * MySQL -> ElasticSearch リカバリツール.
 */
public class Recovery {

    private static Logger log = LoggerFactory.getLogger(Recovery.class);

    private static final String ES_HOSTS = "com.fujitsu.dc.core.es.hosts";
    private static final String ES_CLUSTER_NAME = "com.fujitsu.dc.core.es.cluster.name";
    private static final String ADS_JDBC_URL = "com.fujitsu.dc.core.es.ads.jdbc.url";
    private static final String ADS_JDBC_USER = "com.fujitsu.dc.core.es.ads.jdbc.user";
    private static final String ADS_JDBC_PASSWORD = "com.fujitsu.dc.core.es.ads.jdbc.password";
    private static final String ES_ROUTING_FLAG = "com.fujitsu.dc.core.es.routingFlag";
    static final String EXECUTE_COUNT = "com.fujitsu.dc.core.execute.count";
    static final String CHECK_COUNT = "com.fujitsu.dc.core.es.bulk.check.count";
    private static final String UNIT_PREFIX = "com.fujitsu.dc.core.es.unitPrefix";
    private static String versionNumber = "";

    /**
     * コンストラクタ.
     */
    private Recovery() {
    }

    /**
     * main.
     * @param args 引数
     */
    public static void main(String[] args) {
        loadProperties();
        Option optIndex = new Option("i", "index", true, "リストア対象のインデックス。");
        Option optProp = new Option("p", "prop", true, "プロパティファイル。");
        // tオプションは廃止されたが下位互換性を保つために引数としては受け付けて無視する仕様とする
        Option optType = new Option("t", "type", true, "処理対象のtype。");
        Option optClear = new Option("c", "clear", false, "リストア処理前にelasticsearchをクリアする");
        Option optReplicas = new Option("r", "replicas", true, "リストア後に設定するレプリカ数。");
        Option optVersion = new Option("v", "version", false, "バージョン情報を表示する");
        // 必須
        // optIndex.setRequired(true);
//        optProp.setRequired(true);
        Options options = new Options();
        options.addOption(optIndex);
        options.addOption(optProp);
        options.addOption(optType);
        options.addOption(optClear);
        options.addOption(optReplicas);
        options.addOption(optVersion);
        CommandLineParser parser = new GnuParser();
        CommandLine commandLine = null;
        try {
            commandLine = parser.parse(options, args, true);
        } catch (ParseException e) {
            (new HelpFormatter()).printHelp("com.fujitsu.dc.recovery.Recovery", options);
            log.warn("Recovery failure");
            System.exit(1);
        }

        if (commandLine.hasOption("v")) {
            log.info("Version:" + versionNumber);
            System.exit(0);
        }
        if (!commandLine.hasOption("p")) {
            (new HelpFormatter()).printHelp("com.fujitsu.dc.recovery.Recovery", options);
            log.warn("Recovery failure");
            System.exit(1);
        }
        if (commandLine.hasOption("t")) {
            log.info("Command line option \"t\" or \"type\" is deprecated. Option ignored.");
        }
        if (!commandLine.hasOption("r")) {
            (new HelpFormatter()).printHelp("com.fujitsu.dc.recovery.Recovery", options);
            log.warn("Command line option \"r\" is required.");
            System.exit(1);
        }

        RecoveryManager recoveryManager = new RecoveryManager();
        // 指定されたindex
        recoveryManager.setIndexNames(commandLine.getOptionValue("i"));
        // elasticsearchをクリア指定
        recoveryManager.setClear(commandLine.hasOption("c"));

        // リストア後に設定するレプリカ数を設定
        // 0 以上の整数（ESクラスタのノード数まではわからないのでintの範囲でチェック）であること
        try {
            int replicas = Integer.parseInt(commandLine.getOptionValue("r"));
            if (replicas < 0) {
                log.warn("Command line option \"r\"'s value is not integer.");
                System.exit(1);
            }
            recoveryManager.setReplicas(replicas);
        } catch (NumberFormatException e) {
            log.warn("Command line option \"r\"'s value is not integer.");
            System.exit(1);
        }

        try {
            // Propertiesオブジェクトを生成
            Properties properties = new Properties();
            // ファイルを読み込む
            properties.load(new FileInputStream(commandLine.getOptionValue("p")));
            if ((!properties.containsKey(ES_HOSTS))
            || (!properties.containsKey(ES_CLUSTER_NAME))
            || (!properties.containsKey(ADS_JDBC_URL))
            || (!properties.containsKey(ADS_JDBC_USER))
            || (!properties.containsKey(ADS_JDBC_PASSWORD))
            || (!properties.containsKey(ES_ROUTING_FLAG))) {
                log.warn("properties file error");
                log.warn("Recovery failure");
                System.exit(1);
            } else {
                recoveryManager.setEsHosts(properties.getProperty(ES_HOSTS));
                recoveryManager.setEsClusetrName(properties.getProperty(ES_CLUSTER_NAME));
                recoveryManager.setAdsJdbcUrl(properties.getProperty(ADS_JDBC_URL));
                recoveryManager.setAdsUser(properties.getProperty(ADS_JDBC_USER));
                recoveryManager.setAdsPassword(properties.getProperty(ADS_JDBC_PASSWORD));
                recoveryManager.setExecuteCnt(properties.getProperty(EXECUTE_COUNT));
                recoveryManager.setCheckCount(properties.getProperty(CHECK_COUNT));
                recoveryManager.setUnitPrefix(properties.getProperty(UNIT_PREFIX));
            }
        } catch (FileNotFoundException e) {
            e.printStackTrace();
            log.warn("properties file error");
            log.warn("Recovery failure");
            System.exit(1);
        } catch (IOException e) {
            e.printStackTrace();
            log.warn("properties file error");
            log.warn("Recovery failure");
            System.exit(1);
        }

        String [] indexList = recoveryManager.getIndexNames();
        boolean isClear = recoveryManager.isClear();
        if (isClear && (indexList != null && null != indexList[0])) {
            String ad = recoveryManager.getUnitPrefix() + "_" + EsIndex.CATEGORY_AD;
            if (Arrays.asList(indexList).contains(ad)) {
                log.warn("Cannot specify both -c and -i "
            + recoveryManager.getUnitPrefix() + "_ad option.");
                log.warn("Recovery failure");
                System.exit(1);
            }
        }

        // 二重起動抑止のためのロック取得
        try {
            LockUtility.lock();
        } catch (AlreadyStartedException e) {
            log.info("Recovery has already started");
            log.info("Recovery failure");
            return;
        } catch (Exception e) {
            log.error("Failed to get lock for the double start control");
            e.printStackTrace();
            LockUtility.release();
            log.error("Recovery failure");
            System.exit(1);
        }

        // リカバリの実行
        try {
            recoveryManager.recovery();
        } catch (Exception e) {
            LockUtility.release();
            log.error("Recovery failure");
            System.exit(1);
        }
        LockUtility.release();
        log.info("Recovery Success");
        return;
    }

    private static void loadProperties() {
        Properties properties = new Properties();
        InputStream is = Recovery.class.getClassLoader().getResourceAsStream("dc-recovery.properties");
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
        versionNumber = properties.getProperty("com.fujitsu.dc.recovery.version");
    }

}
