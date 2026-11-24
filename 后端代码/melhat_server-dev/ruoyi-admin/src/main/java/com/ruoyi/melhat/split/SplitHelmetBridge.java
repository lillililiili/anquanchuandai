package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.JSONObject;
import java.util.List;

/** The asset ledger, rather than a vendor list, is the authority for split helmets. */
public interface SplitHelmetBridge {
    boolean isRegistered(String sn);
    /** Source classification is independent from whether control is currently enabled. */
    default boolean ownsIdentity(String sn) { return isRegistered(sn); }
    List<String> registered();
    JSONObject capture(String sn, String receivedAt);
    /** Historical ownership from a trustworthy file timestamp, or null when it cannot be resolved. */
    default JSONObject captureFile(String sn, String observedAt) { return null; }
    /** Durable envelope: ingressId, deviceId, kind, payload, captured, receivedAt, receivedMillis, observedAt. */
    void ingest(JSONObject envelope);
}
