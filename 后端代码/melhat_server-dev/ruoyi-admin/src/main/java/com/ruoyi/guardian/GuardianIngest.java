package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * 安全帽上报成功后写入同一份监护快照。只处理快照里的安全帽。
 * 直连帽保留原始地理坐标；旧示意图投影只用于原有适配器。
 */
@Service
public class GuardianIngest {
    private static final double CENTER_LON = 112.574204;
    private static final double CENTER_LAT = 35.466123;
    private static final double HALF_LON = 0.009;
    private static final double HALF_LAT = 0.0055;
    private static final String TIME_PATTERN = "yyyy-MM-dd HH:mm:ss";

    private final GuardianStore store;

    public GuardianIngest(GuardianStore store) {
        this.store = store;
    }

    /** Capture ownership before opening the report database transaction. */
    public JSONObject captureDirect(String deviceId) {
        return captureDevice(deviceId,false);
    }
    public JSONObject captureBelt(String deviceId) {return captureDevice(deviceId,true);}
    private JSONObject captureDevice(String deviceId,boolean isBelt) {
        JSONObject state = store.snapshot();
        Helmet h = isBelt?belt(state,deviceId):helmet(state,deviceId);
        if(h==null || !(isBelt?"DIRECT_BELT":"DIRECT_HELMET").equals(h.device.getString("source")))
            throw new IllegalArgumentException("设备登记或领用已变化");
        JSONObject binding=null,previousBinding=null;
        for(Object raw:WearableModel.rows(state,"bindings")) {
            JSONObject candidate=(JSONObject)raw;
            if(!deviceId.equals(candidate.getString("deviceId"))) continue;
            if(candidate.get("end")==null) {binding=candidate;break;}
            if(previousBinding==null || candidate.getString("end").compareTo(previousBinding.getString("end"))>0) previousBinding=candidate;
        }
        if(binding==null) binding=previousBinding;
        return WearableModel.object("device",WearableModel.copy(h.device),"person",h.person==null?null:WearableModel.copy(h.person),
                "personId",h.personId,"personName",h.personName,"station",h.station,
                "bindingId",binding==null?null:binding.getString("id"),"bindingStart",binding==null?null:binding.getString("start"),
                "bindingEnd",binding==null?null:binding.getString("end"),
                "siteId",h.device.getString("siteId"),"areaId",h.person==null?h.device.getString("areaId"):h.person.getString("areaId"),
                "work",currentWork(state,h.personId,day(new Date())));
    }

    public void directLocation(JSONObject point) {
        store.update(state -> {
            Helmet h=helmet(state,point.getString("deviceId"));
            if(h==null) return false;
            for(Object raw:WearableModel.rows(state,"locations"))
                if(java.util.Objects.equals(point.getString("id"),((JSONObject)raw).getString("id"))) return false;
            JSONObject fix=WearableModel.copy(point);
            fix.remove("device");fix.remove("person");fix.remove("work");
            fix.put("lng",point.get("longitude"));fix.put("lat",point.get("latitude"));
            fix.put("time",point.get("receivedAt"));fix.put("inside",false);
            fix.put("locationTimeBasis",PersonLocationProjection.timeBasis(point));
            JSONArray history=array(state,"locations");history.add(0,fix);
            // SQL is the full history. Keep only a bounded recent view in the shared snapshot.
            int count=0;
            for(int i=0;i<history.size();i++) if("direct-helmet".equals(history.getJSONObject(i).getString("source")) && ++count>2000) history.remove(i--);
            if(h.person!=null && PersonLocationProjection.sameBinding(state,h.deviceId,point,point.getString("receivedAt"))) {
                String previous=h.person.getString("locationReportedAt");
                Date previousTime=parseTime(previous), current=parseTime(point.getString("receivedAt"));
                if(current!=null && (previousTime==null || !current.before(previousTime))) {
                    noteGeographicFences(state,h,point,current);
                    for(String key:new String[]{"longitude","latitude","coordinateSystem","locationSource","accuracyMeters","locationQuality"}) h.person.put(key,point.get(key));
                    h.person.put("locationDeviceId",h.deviceId);
                    h.person.put("locationReportedAt",point.get("receivedAt"));
                    h.person.put("locationTimeBasis",PersonLocationProjection.timeBasis(point));
                    h.person.put("locationFreshness","CURRENT");
                    h.person.put("locationValid","valid".equals(point.getString("locationQuality")));
                    h.person.put("updated",minute(current));
                }
            }
            state.put("seq",state.getIntValue("seq")+1);
            return true;
        });
    }

    /** Idempotent projection from a durable immutable envelope, including original ownership. */
    public void projectDirectEvent(JSONObject envelope) {
        // A later report may reach the file store before the first report's recovery attempt.
        // Always create the case from its first committed evidence, then append this source.
        JSONObject initial=envelope.getJSONObject("initialReport");
        if(initial!=null) projectDirectEvent(initial);
        store.update(state -> {
            String eventId=envelope.getString("eventId");
            JSONObject existing=WearableModel.find(state,"events",eventId);
            if(existing!=null) {
                if(!appendReport(existing,envelope)) return false;
                existing.put("version",existing.getIntValue("version")+1);
                array(existing,"timeline").add(WearableModel.object("time",envelope.get("receivedAt"),
                        "text","设备再次上报同类告警，已合并至此事件（累计 "+existing.getIntValue("reportCount")+" 次）"));
                state.put("seq",state.getIntValue("seq")+1);
                return true;
            }
            JSONObject device=envelope.getJSONObject("device"), person=envelope.getJSONObject("person");
            if(device==null) throw new IllegalArgumentException("安全帽事件缺少归属快照");
            Helmet h=new Helmet(device,envelope.getString("personId"),envelope.getString("personName"),envelope.getString("station"),person);
            boolean sos="ca_sip_sos".equals(envelope.getString("act"));
            String type=envelope.getString("rawType");
            Date when=parseTime(envelope.getString("receivedAt"));
            addEvent(state,h,when,sos?"安全帽发起 SOS":"安全帽告警"+(type==null?"":"（"+type+"）"),
                    sos?"人员求助":"设备通信","helmet-event:"+eventId,type);
            JSONObject event=WearableModel.find(state,"events",eventId);
            event.put("protocol","direct-helmet");
            event.put("sourceRecordType",envelope.get("sourceRecordType"));event.put("sourceRecordId",envelope.get("sourceRecordId"));
            event.put("eventGroupKey",envelope.get("eventGroupKey"));
            event.put("bindingId",envelope.get("bindingId"));
            appendReport(event,envelope);
            event.put("siteId",envelope.get("siteId"));event.put("areaId",envelope.get("areaId"));
            event.put("createdAt",envelope.get("receivedAt"));
            event.put("locationLng",envelope.get("longitude"));event.put("locationLat",envelope.get("latitude"));
            event.put("coordinateSystem",envelope.get("coordinateSystem"));event.put("locationQuality",envelope.get("locationQuality"));
            event.put("locationSource",envelope.get("locationSource"));event.put("accuracyMeters",envelope.get("accuracyMeters"));
            event.put("locationReportedAt",envelope.get("locationReportedAt"));
            JSONObject work=envelope.getJSONObject("work");
            event.put("workId",work==null?"":work.getString("id"));
            event.getJSONObject("snapshot").put("workName",work==null?"待分配":work.getString("name"));
            state.put("seq",state.getIntValue("seq")+1);
            return true;
        });
    }

    private static boolean appendReport(JSONObject event,JSONObject envelope) {
        JSONArray reports=array(event,"sourceRecords");
        String source=envelope.getString("sourceRecordType");Long id=envelope.getLong("sourceRecordId");
        for(Object raw:reports) {
            JSONObject report=(JSONObject)raw;
            if(java.util.Objects.equals(source,report.getString("type")) && java.util.Objects.equals(id,report.getLong("id"))) return false;
        }
        reports.add(WearableModel.object("type",source,"id",id,"receivedAt",envelope.get("receivedAt")));
        event.put("reportCount",reports.size());
        Date previous=parseTime(event.getString("lastReportedAt")), current=parseTime(envelope.getString("receivedAt"));
        if(previous==null || current!=null&&!current.before(previous)) event.put("lastReportedAt",envelope.get("receivedAt"));
        return true;
    }

    private static void noteGeographicFences(JSONObject state,Helmet h,JSONObject point,Date when) {
        String cs=point.getString("coordinateSystem");
        h.person.put("fenceEvaluation","COORDINATE_SYSTEM_UNKNOWN");
        if(!"valid".equals(point.getString("locationQuality"))||!PersonLocationProjection.knownCoordinateSystem(cs)) return;
        h.person.put("fenceEvaluation","NO_MATCHING_FENCE");
        for(Object raw:WearableModel.rows(state,"fences")) {
            JSONObject fence=(JSONObject)raw;
            if(!fence.getBooleanValue("enabled") || fence.getBooleanValue("archived") || !java.util.Objects.equals(h.station,fence.getString("station"))
                    || !contains(fence.getJSONArray("members"),h.personId)) continue;
            if(!java.util.Objects.equals(cs,fence.getString("coordinateSystem"))) { h.person.put("fenceEvaluation","COORDINATE_SYSTEM_MISMATCH");continue; }
            // Coarse/network fixes do not establish a precise fence crossing.
            Double accuracy=point.getDouble("accuracyMeters");
            if(accuracy==null || accuracy<=0 || accuracy>50) {h.person.put("fenceEvaluation","INSUFFICIENT_ACCURACY");continue;}
            h.person.put("fenceEvaluation","EVALUATED");
            if(!cs.equals(h.person.getString("coordinateSystem")) || !"CURRENT".equals(h.person.getString("locationFreshness"))
                    || !h.person.getBooleanValue("locationValid")) continue;
            Date previous=parseTime(h.person.getString("locationReportedAt"));
            if(previous==null || when.getTime()-previous.getTime()>45000) continue;
            JSONArray polygon=fence.getJSONArray("points");
            double lon=point.getDoubleValue("longitude"),lat=point.getDoubleValue("latitude");
            // Require the uncertainty disks of both observations to clear every edge.
            Double oldAccuracy=h.person.getDouble("accuracyMeters");
            if(oldAccuracy==null || !clearBoundary(lon,lat,accuracy,polygon)
                    || !clearBoundary(h.person.getDoubleValue("longitude"),h.person.getDoubleValue("latitude"),oldAccuracy,polygon)) continue;
            boolean was=inside(h.person.getDoubleValue("longitude"),h.person.getDoubleValue("latitude"),polygon), now=inside(lon,lat,polygon);
            if(was==now || now&&!fence.getBooleanValue("enter") || !now&&!fence.getBooleanValue("leave")) continue;
            array(state,"fenceRecords").add(0,WearableModel.object("id","FR"+nextSeq(state),"fenceId",fence.getString("id"),
                    "fenceName",fence.getString("name"),"personId",h.personId,"personName",h.personName,"type",now?"进入":"离开",
                    "time",stamp(when),"station",h.station,"coordinateSystem",cs,"longitude",lon,"latitude",lat));
        }
    }

    private static boolean clearBoundary(double lon,double lat,double accuracy,JSONArray polygon) {
        if(polygon==null || polygon.size()<3 || accuracy<=0 || accuracy>50) return false;
        double sx=111320*Math.cos(Math.toRadians(lat)),sy=111320;
        for(int i=0;i<polygon.size();i++) {
            JSONArray a=polygon.getJSONArray(i),b=polygon.getJSONArray((i+1)%polygon.size());
            double ax=(a.getDoubleValue(0)-lon)*sx,ay=(a.getDoubleValue(1)-lat)*sy;
            double bx=(b.getDoubleValue(0)-lon)*sx,by=(b.getDoubleValue(1)-lat)*sy;
            double dx=bx-ax,dy=by-ay,den=dx*dx+dy*dy,t=den==0?0:Math.max(0,Math.min(1,-(ax*dx+ay*dy)/den));
            if(Math.hypot(ax+t*dx,ay+t*dy)<=accuracy) return false;
        }
        return true;
    }

    static boolean directBeltReport(JSONObject state, String deviceId, JSONObject telemetry, boolean saveLocation) {
        return directBeltReport(state,deviceId,telemetry,saveLocation,null);
    }
    static boolean directBeltReport(JSONObject state,String deviceId,JSONObject telemetry,boolean saveLocation,JSONObject captured) {
        Helmet belt = captured==null?belt(state,deviceId):capturedBelt(state,captured);
        if (belt == null) throw new IllegalArgumentException("安全带登记已停用或台账投影缺失");
        if(captured!=null) {
            Helmet current=belt(state,deviceId);
            // Historical attribution is immutable; only the same current wearer receives live position updates.
            belt=new Helmet(belt.device,belt.personId,belt.personName,belt.station,
                    current!=null&&PersonLocationProjection.sameBinding(state,deviceId,captured,telemetry.getString("locationReportedAt"))?current.person:null);
        }
        if (saveLocation && "CURRENT".equals(telemetry.getString("locationFreshness")) && PersonLocationProjection.coordinates(telemetry)) {
            String timestamp=telemetry.getString("locationReportedAt");
            Date when=parseTime(timestamp);
            String sourceKey=deviceId+":belt-location:"+timestamp;
            boolean duplicate=false;
            for(Object raw:WearableModel.rows(state,"locations"))if(sourceKey.equals(((JSONObject)raw).getString("sourceKey"))){duplicate=true;break;}
            if(!duplicate&&when!=null) {
                JSONObject binding=PersonLocationProjection.binding(state,deviceId);
                JSONObject fix=WearableModel.object("id","LOC"+nextSeq(state),"deviceId",deviceId,"personId",belt.personId,
                        "source","direct-belt","sourceKey",sourceKey,"siteId",belt.device.getString("siteId"),"station",belt.station,
                        "longitude",telemetry.get("longitude"),"latitude",telemetry.get("latitude"),
                        "lng",telemetry.get("longitude"),"lat",telemetry.get("latitude"),"time",timestamp,
                        "receivedAt",timestamp,"reportedAt",timestamp,"locationReportedAt",timestamp,"receivedMillis",when.getTime(),
                        "deviceReportedAt",telemetry.get("deviceReportedAt"),"locationTimeBasis","RECEIVED_AT",
                        "coordinateSystem",telemetry.getString("coordinateSystem")==null?"UNKNOWN":telemetry.getString("coordinateSystem"),
                        "locationQuality",telemetry.getString("locationQuality")==null?"unknown":telemetry.getString("locationQuality"),
                        "locationSource",telemetry.getString("locationSource")==null?"UNKNOWN":telemetry.getString("locationSource"),
                        "accuracyMeters",telemetry.get("accuracyMeters"),"inside",false,
                        "bindingId",captured!=null?captured.get("bindingId"):binding==null?null:binding.get("id"));
                // Real geographic observations never use the retired percentage map/fence projection.
                array(state,"locations").add(0,fix);
                if(belt.person!=null&&PersonLocationProjection.sameBinding(state,deviceId,fix,timestamp)) {
                    Date previous=parseTime(belt.person.getString("locationReportedAt"));
                    if(previous==null||!when.before(previous))noteGeographicFences(state,belt,fix,when);
                }
            }
        }
        JSONObject current=WearableModel.find(state,"devices",deviceId);
        Date latest=current==null?null:parseTime(current.getString("lastSeenAt")),received=parseTime(telemetry.getString("lastSeenAt"));
        if(current!=null&&(latest==null||received!=null&&!received.before(latest)))DirectBeltProjection.applyStatus(current,telemetry);
        state.put("seq", state.getIntValue("seq") + 1);
        return true;
    }

    static boolean directBeltAlarm(JSONObject state, String deviceId, String rawType, String timestamp, boolean sos) {
        return directBeltAlarm(state,deviceId,rawType,timestamp,sos,null);
    }
    static boolean directBeltAlarm(JSONObject state,String deviceId,String rawType,String timestamp,boolean sos,JSONObject captured) {
        Helmet belt = captured==null?belt(state,deviceId):capturedBelt(state,captured);
        if (belt == null) throw new IllegalArgumentException("安全带登记已停用或台账投影缺失");
        Date when = parseTime(timestamp);
        if (when == null) when = new Date();
        String code = rawType == null ? "" : rawType.substring(0, Math.min(64, rawType.length()));
        addEvent(state, belt, when, sos ? "安全带发起 SOS" : "安全带告警" + (code.isEmpty() ? "" : "（" + code + "）"),
                sos ? "人员求助" : "设备通信", timestamp == null ? null
                        : deviceId + ":belt:" + (sos ? "sos:" : "alarm:") + code + ":" + timestamp, code);
        return true;
    }
    private static Helmet capturedBelt(JSONObject state,JSONObject captured){
        JSONObject d=WearableModel.copy(captured.getJSONObject("device")),p=captured.getJSONObject("person");
        return new Helmet(d,captured.getString("personId"),captured.getString("personName"),captured.getString("station"),p==null?null:WearableModel.copy(p));
    }

    /** The shared ledger projection supplies attribution; incoming user_id is never considered. */
    private static Helmet belt(JSONObject state, String deviceId) {
        JSONObject device = WearableModel.find(state, "devices", deviceId);
        if (device == null || !"B".equals(device.getString("type"))
                || !"DIRECT_BELT".equals(device.getString("source")) || !device.getBooleanValue("active")) return null;
        JSONObject binding = null;
        for (Object raw : WearableModel.rows(state, "bindings")) {
            JSONObject candidate = (JSONObject) raw;
            if (!deviceId.equals(candidate.getString("deviceId")) || candidate.get("end") != null) continue;
            if (binding != null) throw new IllegalArgumentException("安全带领用关系冲突");
            binding = candidate;
        }
        if (binding == null) return new Helmet(device, "", "未关联人员", device.getString("station"), null);
        JSONObject person = WearableModel.find(state, "people", binding.getString("personId"));
        if (person == null || !person.getBooleanValue("active")
                || !java.util.Objects.equals(device.getString("station"), person.getString("station"))
                || !java.util.Objects.equals(device.getString("siteId"), person.getString("siteId")))
            throw new IllegalArgumentException("安全带领用人员或厂站无效");
        return new Helmet(device, person.getString("id"), person.getString("name"), device.getString("station"), person);
    }

    public void directTelemetry(final String deviceId, final JSONObject telemetry) {
        if (telemetry == null) return;
        store.update(state -> {
            Helmet helmet = helmet(state, deviceId);
            if (helmet == null || !"DIRECT_HELMET".equals(helmet.device.getString("source"))) return false;
            DirectHelmetProjection.applyStatus(helmet.device, telemetry);
            return true;
        });
    }

    /** Unknown vendor alarm codes remain identifiable without guessing their safety meaning. */
    public void directAlarm(final String deviceId, final String rawType, final String timestamp) {
        store.update(state -> {
            Helmet helmet = helmet(state, deviceId);
            if (helmet == null) return false;
            Date when = parseTime(timestamp);
            if (when == null) when = new Date();
            String code = rawType == null ? "" : rawType.substring(0, Math.min(64, rawType.length()));
            addEvent(state, helmet, when, "安全帽告警" + (code.isEmpty() ? "" : "（" + code + "）"),
                    "设备通信", timestamp == null ? null : deviceId + ":alarm:" + code + ":" + timestamp, code);
            return true;
        });
    }

    public void alarm(final String helmetSn, final String type, final String startTime) {
        store.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject state) {
                Helmet helmet = helmet(state, helmetSn);
                if (helmet == null) return false;
                Date when = parseTime(startTime);
                if (when == null) when = new Date();
                markHeard(helmet, when);
                addEvent(state, helmet, when, title(type), portalType(type), startTime == null ? null : helmetSn + ":" + type + ":" + startTime);
                return true;
            }
        });
    }

    public void location(final String helmetSn, final String longitude, final String latitude, final String timestamp) {
        store.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject state) {
                Helmet helmet = helmet(state, helmetSn);
                if (helmet == null) return false;
                Date when = parseTime(timestamp);
                if (when == null) when = new Date();
                return move(state, helmet, longitude, latitude, when);
            }
        });
    }

    public void sos(final String helmetSn, final String longitude, final String latitude) { sos(helmetSn, longitude, latitude, null); }

    public void sos(final String helmetSn, final String longitude, final String latitude, final String timestamp) {
        store.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject state) {
                Helmet helmet = helmet(state, helmetSn);
                if (helmet == null) return false;
                Date when = parseTime(timestamp);
                if (when == null) when = new Date();
                markHeard(helmet, when);
                addEvent(state, helmet, when, "安全帽发起 SOS", "人员求助", timestamp == null ? null : helmetSn + ":sos:" + timestamp);
                if (longitude != null && latitude != null && longitude.trim().length() > 0 && latitude.trim().length() > 0) {
                    move(state, helmet, longitude, latitude, when);
                }
                return true;
            }
        });
    }

    private static void addEvent(JSONObject state, Helmet helmet, Date when, String title, String type, String sourceKey) {
        addEvent(state, helmet, when, title, type, sourceKey, null);
    }

    private static void addEvent(JSONObject state, Helmet helmet, Date when, String title, String type, String sourceKey, String rawType) {
        if (sourceKey != null) for (Object raw : WearableModel.rows(state, "events")) if (sourceKey.equals(((JSONObject)raw).getString("sourceKey"))) return;
        String day = day(when);
        String clock = minute(when);
        JSONObject work = currentWork(state, helmet.personId, day);
        int seq = nextSeq(state);
        String mmdd = day.length() >= 10 ? day.substring(5, 7) + day.substring(8, 10) : "0000";
        JSONObject event = new JSONObject();
        event.put("id", sourceKey!=null&&sourceKey.startsWith("helmet-event:")?sourceKey.substring(13):"RL-E-" + mmdd + "-" + String.format("%03d", seq));
        event.put("personId", helmet.personId);
        event.put("deviceId", helmet.deviceId);
        event.put("workId", work == null ? "" : work.getString("id"));
        event.put("title", title);
        event.put("type", type);
        event.put("status", "待认领");
        event.put("source", "device");
        event.put("sourceKey", sourceKey);
        if (rawType != null) event.put("rawAlarmType", rawType);
        event.put("siteId", helmet.device.getString("siteId"));
        event.put("areaId", helmet.device.getString("areaId"));
        event.put("version", 1);
        event.put("createdAt", java.time.Instant.now().toString());
        event.put("time", clock);
        event.put("externalStatus", "未接入外部系统");
        event.put("station", helmet.station);
        event.put("date", day);
        event.put("externalId", "");
        JSONObject snapshot = new JSONObject();
        snapshot.put("personName", helmet.personName);
        snapshot.put("deviceId", helmet.deviceId);
        snapshot.put("workName", work == null ? "待分配" : work.getString("name"));
        if ("DIRECT_BELT".equals(helmet.device.getString("source"))) {
            event.put("protocol", "direct-belt");
            snapshot.put("personId", helmet.personId);
            snapshot.put("siteId", helmet.device.getString("siteId"));
            snapshot.put("station", helmet.station);
            snapshot.put("deviceNumber", helmet.device.getString("deviceNumber"));
            snapshot.put("code", helmet.device.getString("code"));
            snapshot.put("sn", helmet.device.getString("sn"));
        }
        event.put("snapshot", snapshot);
        event.put("draft", null);
        event.put("verification", null);
        JSONArray timeline = new JSONArray();
        JSONObject line = new JSONObject();
        line.put("time", clock);
        line.put("text", "检测到" + title);
        timeline.add(line);
        event.put("timeline", timeline);
        JSONArray events = array(state, "events");
        events.add(0, event);
        GuardianEvents.normalize(state);
    }

    private static boolean move(JSONObject state, Helmet helmet, String longitude, String latitude, Date when) {
        double lon;
        double lat;
        try {
            lon = Double.parseDouble(longitude.trim());
            lat = Double.parseDouble(latitude.trim());
        } catch (RuntimeException ignored) {
            return false;
        }
        if (!Double.isFinite(lon) || !Double.isFinite(lat) || Math.abs(lon) > 180 || Math.abs(lat) > 90
                || (lon == 0 && lat == 0)) return false;
        double x = ((lon - (CENTER_LON - HALF_LON)) / (HALF_LON * 2)) * 100;
        double y = ((CENTER_LAT + HALF_LAT - lat) / (HALF_LAT * 2)) * 100;
        boolean inside = x >= 0 && x <= 100 && y >= 0 && y <= 100;
        markHeard(helmet, when);
        JSONArray position = helmet.person == null ? null : helmet.person.getJSONArray("position");
        Date previousLocation = helmet.person == null ? null : parseTime(helmet.person.getString("locationReportedAt"));
        boolean latest = previousLocation == null || !when.before(previousLocation);
        if (inside && helmet.person != null && latest) {
            double nx = round(x);
            double ny = round(y);
            noteFences(state, helmet, position, nx, ny, when);
            JSONArray next = new JSONArray();
            next.add(nx);
            next.add(ny);
            helmet.person.put("position", next);
            helmet.person.put("locationValid", true);
            helmet.person.put("updated", minute(when));
            helmet.person.put("locationDeviceId", helmet.deviceId);
            helmet.person.put("locationReportedAt", when.toInstant().toString());
        } else if (position != null && helmet.person != null && latest) {
            helmet.person.put("locationValid", false);
            helmet.person.put("locationDeviceId", helmet.deviceId);
            helmet.person.put("locationReportedAt", when.toInstant().toString());
        }
        JSONObject fix = new JSONObject();
        fix.put("id", "LOC" + nextSeq(state));
        fix.put("personId", helmet.personId);
        fix.put("deviceId", helmet.deviceId);
        fix.put("lng", longitude);
        fix.put("lat", latitude);
        fix.put("time", stamp(when));
        fix.put("inside", inside);
        if (inside) {
            fix.put("x", round(x));
            fix.put("y", round(y));
        }
        array(state, "locations").add(0, fix);
        return true;
    }

    private static void noteFences(JSONObject state, Helmet helmet, JSONArray before, double x, double y, Date when) {
        if (before == null || before.size() < 2) return;
        JSONArray fences = state.getJSONArray("fences");
        if (fences == null) return;
        double ox = before.getDoubleValue(0);
        double oy = before.getDoubleValue(1);
        for (int i = 0; i < fences.size(); i++) {
            JSONObject fence = fences.getJSONObject(i);
            if (fence == null || !fence.getBooleanValue("enabled") || fence.getBooleanValue("archived")) continue;
            if (!helmet.station.equals(fence.getString("station"))) continue;
            if (!contains(fence.getJSONArray("members"), helmet.personId)) continue;
            JSONArray points = fence.getJSONArray("points");
            boolean was = inside(ox, oy, points);
            boolean now = inside(x, y, points);
            if (was == now) continue;
            if (now && !fence.getBooleanValue("enter")) continue;
            if (!now && !fence.getBooleanValue("leave")) continue;
            JSONObject record = new JSONObject();
            record.put("id", "FR" + nextSeq(state));
            record.put("fenceId", fence.getString("id"));
            record.put("fenceName", fence.getString("name"));
            record.put("personId", helmet.personId);
            record.put("personName", helmet.personName);
            record.put("type", now ? "进入" : "离开");
            record.put("time", stamp(when));
            record.put("station", helmet.station);
            array(state, "fenceRecords").add(0, record);
        }
    }

    private static boolean inside(double x, double y, JSONArray polygon) {
        if (polygon == null) return false;
        boolean yes = false;
        int count = polygon.size();
        for (int i = 0, j = count - 1; i < count; j = i++) {
            JSONArray a = polygon.getJSONArray(i);
            JSONArray b = polygon.getJSONArray(j);
            if (a == null || b == null) continue;
            double xi = a.getDoubleValue(0);
            double yi = a.getDoubleValue(1);
            double xj = b.getDoubleValue(0);
            double yj = b.getDoubleValue(1);
            if ((yi > y) != (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) yes = !yes;
        }
        return yes;
    }

    private static Helmet helmet(JSONObject state, String helmetSn) {
        if (helmetSn == null || helmetSn.trim().isEmpty()) return null;
        JSONArray devices = state.getJSONArray("devices");
        if (devices == null) return null;
        JSONObject device = null;
        for (int i = 0; i < devices.size(); i++) {
            JSONObject item = devices.getJSONObject(i);
            if (item != null && helmetSn.equals(item.getString("id")) && "H".equals(item.getString("type"))) {
                device = item;
                break;
            }
        }
        if (device == null || !device.getBooleanValue("active")) return null;
        JSONArray bindings = state.getJSONArray("bindings");
        if (bindings == null) return null;
        String personId = null;
        for (int i = 0; i < bindings.size(); i++) {
            JSONObject binding = bindings.getJSONObject(i);
            if (binding == null || binding.get("end") != null) continue;
            if (helmetSn.equals(binding.getString("deviceId"))) {
                personId = binding.getString("personId");
                break;
            }
        }
        if (personId == null) return new Helmet(device, "", "未关联人员", device.getString("station"), null);
        JSONArray people = state.getJSONArray("people");
        if (people == null) return null;
        for (int i = 0; i < people.size(); i++) {
            JSONObject person = people.getJSONObject(i);
            if (person != null && personId.equals(person.getString("id")) && person.getBooleanValue("active")) {
                return new Helmet(device, personId, person.getString("name"), person.getString("station"), person);
            }
        }
        return null;
    }

    private static JSONObject currentWork(JSONObject state, String personId, String day) {
        JSONArray works = state.getJSONArray("works");
        if (works == null) return null;
        for (int i = 0; i < works.size(); i++) {
            JSONObject work = works.getJSONObject(i);
            if (work == null || GuardianDemoData.confirmed(work) || !day.equals(work.getString("date")) || "已结束".equals(work.getString("status"))) continue;
            if (contains(work.getJSONArray("members"), personId)) return work;
        }
        return null;
    }

    private static boolean contains(JSONArray list, String id) {
        if (list == null || id == null) return false;
        for (int i = 0; i < list.size(); i++) {
            if (id.equals(list.getString(i))) return true;
        }
        return false;
    }

    private static JSONArray array(JSONObject state, String name) {
        JSONArray list = state.getJSONArray(name);
        if (list == null) {
            list = new JSONArray();
            state.put(name, list);
        }
        return list;
    }

    private static int nextSeq(JSONObject state) {
        int seq = state.getIntValue("seq") + 1;
        state.put("seq", seq);
        return seq;
    }

    private static Date portalNow(JSONObject state) {
        String day = "2026-09-15";
        JSONArray events = state.getJSONArray("events");
        if (events != null && !events.isEmpty() && events.getJSONObject(0) != null) {
            String found = events.getJSONObject(0).getString("date");
            if (found != null && found.length() == 10) day = found;
        }
        int clock = state.getIntValue("clock");
        String text = String.format("%s %02d:%02d:%02d", day, (clock / 3600) % 24, (clock / 60) % 60, clock % 60);
        Date parsed = parseTime(text);
        return parsed == null ? new Date(0) : parsed;
    }

    private static Date parseTime(String text) {
        if (text == null || text.trim().isEmpty()) return null;
        try { return Date.from(java.time.Instant.parse(text.trim())); }
        catch (java.time.format.DateTimeParseException ignored) {}
        try {
            return new SimpleDateFormat(TIME_PATTERN).parse(text.trim());
        } catch (ParseException e) {
            return null;
        }
    }

    private static String day(Date date) {
        return new SimpleDateFormat("yyyy-MM-dd").format(date);
    }

    private static String minute(Date date) {
        return new SimpleDateFormat("HH:mm").format(date);
    }

    private static String stamp(Date date) {
        return new SimpleDateFormat(TIME_PATTERN).format(date);
    }

    private static double round(double value) {
        return Math.round(value * 100) / 100.0;
    }

    private static void markHeard(Helmet helmet, Date when) {
        helmet.device.put("online", true);
        helmet.device.put("updated", stamp(when));
    }

    private static String title(String type) {
        if ("silent".equals(type)) return "静默报警";
        if ("removal".equals(type)) return "脱帽报警";
        if ("fall".equals(type)) return "跌落报警";
        if ("proximity".equals(type)) return "近电感应报警";
        if ("sos".equals(type)) return "安全帽发起 SOS";
        return "安全帽告警";
    }

    private static String portalType(String type) {
        if ("silent".equals(type) || "sos".equals(type)) return "人员求助";
        if ("fall".equals(type)) return "位置异常";
        return "设备通信";
    }

    private static final class Helmet {
        private final JSONObject device;
        private final String deviceId;
        private final String personId;
        private final String personName;
        private final String station;
        private final JSONObject person;

        private Helmet(JSONObject device, String personId, String personName, String station, JSONObject person) {
            this.device = device;
            this.deviceId = device.getString("id");
            this.personId = personId;
            this.personName = personName;
            this.station = station;
            this.person = person;
        }
    }
}
