package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.*;

/** 厂家列表是身份及通信状态来源；人员、领用、维修和厂站归属由本地台账管理。 */
@Service
public class AdminPlatformService {
    private final AdminLedgerStore ledger;
    private final AdminQueryService queries;
    private final PlatformDeviceSyncService platform;
    public AdminPlatformService(AdminLedgerStore ledger, AdminQueryService queries, PlatformDeviceSyncService platform) {
        this.ledger=ledger;this.queries=queries;this.platform=platform;
    }
    @Transactional(rollbackFor=Exception.class)
    public synchronized JSONObject sync(String accountId, String siteId) throws Exception {
        return sync(accountId,siteId,false);
    }
    @Transactional(rollbackFor=Exception.class)
    public synchronized JSONObject sync(String accountId, String siteId, boolean automatic) throws Exception {
        synchronized (ledger) {
        JSONObject initial=ledger.read();
        JSONObject actor=find(initial.getJSONArray("accounts"),"id",accountId);
        if(actor==null || !actor.getBooleanValue("enabled") || !queries.allows(initial,actor,"assets:write",siteId,null))
            throw AdminQueryService.fail(403,"PERMISSION_DENIED","需要当前厂站的设备管理权限");
        String station=station(initial,siteId);
        List<HeadbandVO> incoming=platform.preview();
        JSONObject state=ledger.read();
        JSONArray devices=state.getJSONArray("devices");
        int added=0, updated=0, skipped=0;
        String now=Instant.now().toString();
        Set<String> seen=new HashSet<>();
        for(HeadbandVO raw:incoming) {
            String sn=raw.getHelmetSn();
            if(sn==null || !sn.matches("[A-Za-z0-9._-]{1,64}") || !seen.add(sn) || !("0".equals(raw.getOnline())||"1".equals(raw.getOnline())))
                throw AdminQueryService.fail(502,"PLATFORM_INVALID","厂家设备编号或状态无效，未同步");
            JSONObject device=null;
            for(Object item:devices) {
                JSONObject row=(JSONObject)item;
                if(sn.equals(row.getString("code"))||sn.equals(row.getString("sn"))) {
                    if(device!=null) throw AdminQueryService.fail(409,"DEVICE_CONFLICT","本地设备编号或SN重复，请先核对");
                    device=row;
                }
            }
            if(device!=null && (!"HELMET".equals(device.getString("type")) || device.getString("code").startsWith("RL-")))
                throw AdminQueryService.fail(409,"DEVICE_CONFLICT","厂家编号与现有其他类型或示例设备冲突");
            if(device!=null && !siteId.equals(device.getString("siteId"))) { skipped++;continue; }
            if(device==null) {
                if(automatic)continue;
                device=new JSONObject();device.put("id","platform-helmet-"+sn);device.put("code",sn);device.put("sn",sn);
                device.put("name","厂家安全帽");device.put("type","HELMET");device.put("siteId",siteId);device.put("areaId",null);
                device.put("lifecycle","STOCK");device.put("relation","UNASSIGNED");device.put("modelId","unknown-HELMET");
                device.put("assemblies",new JSONObject());device.put("verification","UNCONFIRMED");device.put("capability","UNCONFIRMED");
                device.put("capabilitySource","厂家设备列表；佩戴、定位和音视频能力待联调");device.put("version",1);devices.add(device);added++;
            } else { updated++; }
            device.put("source","PLATFORM");device.put("portalDeviceId",sn);device.put("portalStation",station);
            device.put("platformUid",raw.getUid_device());device.put("communication","1".equals(raw.getOnline())?"ONLINE":"OFFLINE");
            device.put("connection","CONNECTED");device.put("freshness","CURRENT");device.put("sourceTime",now);device.put("battery",null);
        }
        // 列表中消失不等于离线或删除，保留资产及领用，仅将通信标记为未知。
        for(Object item:devices) {
            JSONObject d=(JSONObject)item;
            if("PLATFORM".equals(d.getString("source")) && siteId.equals(d.getString("siteId")) && !seen.contains(d.getString("portalDeviceId"))) {
                d.put("communication","NOT_CONNECTED");d.put("freshness","UNKNOWN");
            }
        }
        platform.syncRecords(incoming,actor.getString("loginName"));
        JSONObject info=new JSONObject();info.put("siteId",siteId);info.put("station",station);info.put("lastSuccessAt",now);info.put("status","SUCCESS");
        info.put("platformTotal",incoming.size());info.put("added",added);info.put("updated",updated);info.put("skippedOtherSite",skipped);
        JSONObject sources=state.getJSONObject("platformSync");if(sources==null){sources=new JSONObject();state.put("platformSync",sources);}sources.put(siteId,info);
        JSONObject audit=new JSONObject();audit.put("id","platform-sync-"+UUID.randomUUID());audit.put("siteId",siteId);audit.put("actorId",accountId);
        audit.put("actorName",actor.getString("name"));audit.put("occurredAt",now);audit.put("action","devices.platformSync");audit.put("result","SUCCESS");
        audit.put("objectId","platform-helmets");audit.put("summary","厂家安全帽同步：新增 "+added+"，更新 "+updated);if(!automatic)state.getJSONArray("audit").add(audit);
        state.put("revision",state.getIntValue("revision")+1);ledger.write(state);return info;
        }
    }
    static String station(JSONObject state,String siteId) {
        JSONObject site=find(state.getJSONArray("sites"),"id",siteId);
        if(site==null || !site.getBooleanValue("enabled"))throw AdminQueryService.fail(400,"SITE_INVALID","厂站不存在或已停用");
        String station=site.getString("portalId");
        if(station==null)station="site-1".equals(siteId)?"S1":"site-2".equals(siteId)?"S2":null;
        if(station==null)throw AdminQueryService.fail(400,"SITE_NOT_MAPPED","请先配置厂站的前台映射");return station;
    }
    static JSONObject find(JSONArray rows,String field,String value) {
        if(rows!=null)for(Object item:rows){JSONObject row=(JSONObject)item;if(Objects.equals(value,row.getString(field)))return row;}return null;
    }
}
