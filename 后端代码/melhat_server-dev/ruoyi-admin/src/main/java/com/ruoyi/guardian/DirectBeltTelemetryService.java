package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.util.Objects;
import static com.ruoyi.guardian.WearableModel.*;

/** Authoritative belt registration and durable telemetry/event bridge. Never trusts a device user_id. */
@Service
public class DirectBeltTelemetryService {
    private final AdminLedgerStore ledger;
    private final GuardianStore store;

    public DirectBeltTelemetryService(AdminLedgerStore ledger, GuardianStore store) {
        this.ledger = ledger;
        this.store = store;
    }

    public JSONObject registered(String deviceId) {
        if (deviceId == null || !deviceId.matches("[A-Za-z0-9._-]{1,64}")) return null;
        JSONObject state = ledger.read();
        if (state == null) return null;
        JSONObject device = null;
        for (Object raw : rows(state, "devices")) {
            JSONObject candidate = (JSONObject) raw;
            if (!deviceId.equals(candidate.getString("deviceNumber"))) continue;
            if (device != null) return null;
            device = candidate;
        }
        if (device == null || !"DIRECT_BELT".equals(device.getString("source"))
                || !"BELT".equals(device.getString("type"))
                || !deviceId.equals(device.getString("portalDeviceId"))
                || "DISABLED".equals(device.getString("lifecycle"))
                || "SCRAPPED".equals(device.getString("lifecycle"))) return null;
        JSONObject site = find(state, "sites", device.getString("siteId"));
        if (site == null || !site.getBooleanValue("enabled") || site.getString("portalStation") == null) return null;
        JSONObject result = object("deviceId", deviceId, "ledgerId", device.getString("id"),
                "siteId", site.getString("id"), "station", site.getString("portalStation"),
                "userId", "", "userName", "");
        JSONObject assignment = null;
        for (Object raw : rows(state, "assignments")) {
            JSONObject candidate = (JSONObject) raw;
            if (!candidate.getBooleanValue("active") || !device.getString("id").equals(candidate.getString("deviceId"))) continue;
            if (assignment != null) return null;
            assignment = candidate;
        }
        if (assignment != null && "IN_USE".equals(device.getString("lifecycle"))) {
            JSONObject person = find(state, "people", assignment.getString("personId"));
            if (person == null || !person.getBooleanValue("enabled")
                    || !Objects.equals(site.getString("id"), person.getString("siteId"))
                    || person.getString("portalId") == null) return null;
            result.put("userId", person.getString("portalId"));
            result.put("userName", person.getString("name"));
        }
        return result;
    }

    public void snapshot(String deviceId, JSONObject status) {
        requireStatus(status);
        requireRegistered(deviceId);
        store.update(state -> GuardianIngest.directBeltReport(state, deviceId, status, false));
    }

    public void report(String deviceId, JSONObject status) {
        requireStatus(status);
        requireRegistered(deviceId);
        store.update(state -> GuardianIngest.directBeltReport(state, deviceId, status, true));
    }

    /** The gateway commits its candidate runtime state only after this durable update succeeds. */
    public void receive(String deviceId, JSONObject status, String rawType, String timestamp, boolean sos) {
        requireStatus(status);
        requireRegistered(deviceId);
        store.update(state -> {
            GuardianIngest.directBeltReport(state, deviceId, status, true);
            if (rawType != null || sos) GuardianIngest.directBeltAlarm(state, deviceId, rawType, timestamp, sos);
            return true;
        });
    }
    /** Replay retains reception-time attribution and timestamps, without resurrecting a socket session. */
    public void receiveCaptured(String deviceId,JSONObject status,String rawType,String timestamp,boolean sos,JSONObject context){
        requireStatus(status);
        store.update(state->{GuardianIngest.directBeltReport(state,deviceId,status,true,context);
            if(rawType!=null||sos)GuardianIngest.directBeltAlarm(state,deviceId,rawType,timestamp,sos,context);
            return true;});
    }

    public void alarm(String deviceId, String rawType, String timestamp) {
        alarm(deviceId, rawType, timestamp, false);
    }

    public void alarm(String deviceId, String rawType, String timestamp, boolean sos) {
        requireRegistered(deviceId);
        store.update(state -> GuardianIngest.directBeltAlarm(state, deviceId, rawType, timestamp, sos));
    }

    private void requireRegistered(String deviceId) {
        if (registered(deviceId) == null) throw new IllegalArgumentException("安全带未预先登记或登记已停用");
    }

    private static void requireStatus(JSONObject status) {
        if (status == null) throw new IllegalArgumentException("缺少安全带上报状态");
    }
}
