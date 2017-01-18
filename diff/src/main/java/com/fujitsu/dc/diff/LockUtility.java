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
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;

/**
 * ロックユーティリティ.
 */
public class LockUtility {

    private static FileOutputStream fos = null;
    private static FileChannel fchan = null;
    private static FileLock flock = null;
    private static final String LOCKFILE = "/fj/dc-diff/dc1-diff.lock";

    private LockUtility() {
    }

    /**
     * ロック取得.
     * @throws IOException IO例外
     */
    public static synchronized void lock() throws IOException {
        fos = new FileOutputStream(LOCKFILE);
        fchan = fos.getChannel();
        flock = fchan.tryLock();

        if (null == flock) {
            throw new AlreadyStartedException();
        }
    }

    /**
     * ロック解放.
     * @throws IOException IO例外
     */
    public static void release() throws IOException {
        boolean hasOwnLock = false;
        try {
            if (flock != null) {
                hasOwnLock = true;
                flock.release();
                flock = null;
            }
            if (fchan != null) {
                fchan.close();
                fchan = null;
            }
            if (fos != null) {
                fos.close();
                fos = null;
            }
        } catch (IOException e) {
            throw e;
        } finally {
            if (hasOwnLock) {
                new File(LOCKFILE).delete();
            }
        }

        return;
    }

    /**
     * 整合性チェックツールがすでに起動している場合の例外.
     */
    @SuppressWarnings("serial")
    public static class AlreadyStartedException extends RuntimeException {
    }
}

