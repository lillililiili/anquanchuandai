package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.util.*;

/** Stable identifiers and shared JSON helpers. Display names never identify a person. */
final class WearableModel {
    private WearableModel() {}
    static JSONArray rows(JSONObject state, String key) {
        JSONArray rows = state.getJSONArray(key);
        if (rows == null) { rows = new JSONArray(); state.put(key, rows); }
        return rows;
    }
    static JSONObject find(JSONObject state, String key, String id) {
        if (id == null) return null;
        for (Object raw : rows(state, key)) { JSONObject row = (JSONObject) raw; if (id.equals(row.getString("id"))) return row; }
        return null;
    }
    static JSONObject copy(JSONObject value) { return value == null ? null : JSONObject.parseObject(value.toJSONString()); }
    static JSONObject object(Object... pairs) {
        JSONObject result = new JSONObject();
        for (int i=0;i<pairs.length;i+=2) result.put((String)pairs[i], pairs[i+1]);
        return result;
    }
    static String text(JSONObject body, String key) { String value=body.getString(key); return value==null ? "" : value.trim(); }
    static boolean has(JSONArray rows, String id) { return rows != null && rows.contains(id); }
    static String siteId(JSONObject ledger, String station) {
        if(station==null) return null;
        for(Object raw:rows(ledger,"sites")) { JSONObject row=(JSONObject)raw;
            if(Objects.equals(station,row.getString("portalStation")) || Objects.equals(station,row.getString("id"))) return row.getString("id"); }
        return null;
    }
    static JSONObject person(JSONObject ledger, String portalId) {
        if(portalId==null) return null;
        for(Object raw:rows(ledger,"people")) { JSONObject row=(JSONObject)raw;
            if(Objects.equals(portalId,row.getString("portalId")) || Objects.equals(portalId,row.getString("id"))) return row; }
        return null;
    }
    static JSONObject safe(JSONObject state) { return (JSONObject)sanitize(copy(state)); }
    private static Object sanitize(Object value) {
        if(value instanceof JSONObject) {
            JSONObject object=(JSONObject)value;
            for(String key:new ArrayList<>(object.keySet())) {
                if(key.equals("passwordHash") || key.equals("password") || key.equals("idempotency") || key.equals("eventOperations") || key.equals("uploads") || key.equals("voiceSessions") || key.equals("sharedCommunications")) object.remove(key);
                else object.put(key,sanitize(object.get(key)));
            }
        } else if(value instanceof JSONArray) { JSONArray list=(JSONArray)value; for(int i=0;i<list.size();i++) list.set(i,sanitize(list.get(i))); }
        return value;
    }
    /** Additive migration: keep all existing IDs, roles, references and explicit portal mappings. */
    static boolean migrate(JSONObject state) {
        String before=state.toJSONString();
        for(Object raw:rows(state,"sites")) { JSONObject row=(JSONObject)raw;
            if(text(row,"portalStation").isEmpty()) row.put("portalStation", "site-1".equals(row.getString("id"))?"S1":"site-2".equals(row.getString("id"))?"S2":"SITE-"+row.getString("id")); }
        for(Object raw:rows(state,"people")) { JSONObject row=(JSONObject)raw;
            if(text(row,"portalId").isEmpty()) {
                // One-time mapping of immutable legacy IDs; editable names/codes never drive the mapping.
                String id=row.getString("id");
                row.put("portalId",id.matches("person-1-[0-7]") ? "P"+(Integer.parseInt(id.substring(9))+1) : id);
            }
        }
        for(Object raw:rows(state,"devices")) { JSONObject row=(JSONObject)raw;
            if(text(row,"portalDeviceId").isEmpty()) row.put("portalDeviceId",row.getString("id")); }
        if(!state.getBooleanValue("sharedBusinessV2")) {
            for(Object raw:rows(state,"roles")) { JSONObject role=(JSONObject)raw;
                if(!Arrays.asList("duty","site").contains(role.getString("id"))) continue;
                for(Object grant:rows(role,"grants")) {
                    JSONArray ops=rows((JSONObject)grant,"operations");
                    for(String op:Arrays.asList("events:read","events:claim","events:observe","events:verify","sos:assist","works:read","communications:voice","communications:broadcast")) if(!ops.contains(op)) ops.add(op);
                }
            }
            if(find(state,"roles","mobile-user")==null) {
                JSONArray sites=new JSONArray(); for(Object raw:rows(state,"sites")) sites.add(((JSONObject)raw).getString("id"));
                JSONArray ops=new JSONArray(); ops.addAll(Arrays.asList("self:read","events:observe","sos:create","works:read"));
                JSONArray grants=new JSONArray(); grants.add(object("operations",ops,"siteIds",sites,"areaIds","*"));
                rows(state,"roles").add(object("id","mobile-user","name","普通用户（本人业务）","enabled",true,"builtin",true,"version",1,"grants",grants));
            }
            state.put("sharedBusinessV2",true);
        }
        return !before.equals(state.toJSONString());
    }
}
