package com.ruoyi.guardian;

import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Supplier;

/**
 * Orders alarm admission, file projection and final verification in this single-writer service.
 * Always acquire before either GuardianStore or SQL; never call from a store update callback.
 * SQL group row locks independently protect the durable many-to-one association.
 */
public final class HelmetEventLifecycle {
    private static final ReentrantLock LOCK = new ReentrantLock(true);
    private HelmetEventLifecycle() { }
    public static <T> T coordinate(Supplier<T> operation) {
        LOCK.lock();
        try { return operation.get(); } finally { LOCK.unlock(); }
    }
}
