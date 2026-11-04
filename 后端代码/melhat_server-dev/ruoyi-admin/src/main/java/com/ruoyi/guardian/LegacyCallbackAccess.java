package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.framework.security.filter.LegacyEndpointBoundaryFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import static com.ruoyi.guardian.WearableModel.*;

/** A service credential has an explicit station allowlist; it is not a human administrator. */
@Service
public class LegacyCallbackAccess {
    private final AdminLedgerStore ledger;
    private final Set<String> sites = new HashSet<>();
    public LegacyCallbackAccess(AdminLedgerStore ledger, @Value("${melhat.legacy-callback.allowed-site-ids:}") String siteIds) {
        this.ledger = ledger;
        for (String site : siteIds.split(",")) if (!site.trim().isEmpty()) sites.add(site.trim());
    }
    public void requireDevice(String number) {
        ServletRequestAttributes attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        if (attrs == null || !Boolean.TRUE.equals(attrs.getRequest().getAttribute(LegacyEndpointBoundaryFilter.CALLBACK_AUTHENTICATED)))
            throw AdminQueryService.fail(401, "CALLBACK_AUTHENTICATION_REQUIRED", "设备回调未经认证");
        JSONObject state = ledger.read();
        if (state != null && number != null && !number.trim().isEmpty()) {
            JSONObject matched = null;
            for (Object raw : rows(state, "devices")) {
                JSONObject device = (JSONObject) raw;
                if (!number.equals(device.getString("portalDeviceId")) && !number.equals(device.getString("sn"))) continue;
                // A callback cannot establish ownership when either identity aliases another record.
                if (matched != null)
                    throw AdminQueryService.fail(403, "CALLBACK_DEVICE_AMBIGUOUS", "设备回调标识对应多个台账记录");
                matched = device;
            }
            if (matched != null) {
                JSONObject site = find(state, "sites", matched.getString("siteId"));
                if (site != null && site.getBooleanValue("enabled") && sites.contains(site.getString("id"))
                        && "PLATFORM".equals(matched.getString("source")) && "HELMET".equals(matched.getString("type"))
                        && !Arrays.asList("DISABLED", "SCRAPPED").contains(matched.getString("lifecycle"))) return;
            }
        }
        throw AdminQueryService.fail(403, "CALLBACK_DEVICE_OUT_OF_SCOPE", "设备不在回调授权场站范围");
    }
}
