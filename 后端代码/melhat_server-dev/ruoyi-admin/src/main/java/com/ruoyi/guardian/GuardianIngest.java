package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * 安全帽上报成功后写入同一份监护快照。只处理快照里的安全帽。
 * 坐标按阳城电厂示意范围换成 0–100，和前台 map-geo.js 同一组常数。
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

    public void alarm(final String helmetSn, final String type, final String startTime) {
        store.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject state) {
                Helmet helmet = helmet(state, helmetSn);
                if (helmet == null) return false;
                Date when = parseTime(startTime);
                if (when == null) when = portalNow(state);
                markHeard(helmet, when);
                addEvent(state, helmet, when, title(type), portalType(type));
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
                if (when == null) when = portalNow(state);
                return move(state, helmet, longitude, latitude, when);
            }
        });
    }

    public void sos(final String helmetSn, final String longitude, final String latitude) {
        store.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject state) {
                Helmet helmet = helmet(state, helmetSn);
                if (helmet == null) return false;
                Date when = portalNow(state);
                markHeard(helmet, when);
                addEvent(state, helmet, when, "安全帽发起 SOS", "人员求助");
                if (longitude != null && latitude != null && longitude.trim().length() > 0 && latitude.trim().length() > 0) {
                    move(state, helmet, longitude, latitude, when);
                }
                return true;
            }
        });
    }

    private static void addEvent(JSONObject state, Helmet helmet, Date when, String title, String type) {
        String day = day(when);
        String clock = minute(when);
        JSONObject work = currentWork(state, helmet.personId, day);
        int seq = nextSeq(state);
        String mmdd = day.length() >= 10 ? day.substring(5, 7) + day.substring(8, 10) : "0000";
        JSONObject event = new JSONObject();
        event.put("id", "RL-E-" + mmdd + "-" + String.format("%03d", seq));
        event.put("personId", helmet.personId);
        event.put("deviceId", helmet.deviceId);
        event.put("workId", work == null ? "" : work.getString("id"));
        event.put("title", title);
        event.put("type", type);
        event.put("status", "待认领");
        event.put("time", clock);
        event.put("externalStatus", "待回传");
        event.put("station", helmet.station);
        event.put("date", day);
        event.put("externalId", "HAT-" + seq);
        JSONObject snapshot = new JSONObject();
        snapshot.put("personName", helmet.personName);
        snapshot.put("deviceId", helmet.deviceId);
        snapshot.put("workName", work == null ? "待分配" : work.getString("name"));
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
        double x = ((lon - (CENTER_LON - HALF_LON)) / (HALF_LON * 2)) * 100;
        double y = ((CENTER_LAT + HALF_LAT - lat) / (HALF_LAT * 2)) * 100;
        boolean inside = x >= 0 && x <= 100 && y >= 0 && y <= 100;
        markHeard(helmet, when);
        JSONArray position = helmet.person.getJSONArray("position");
        if (inside) {
            double nx = round(x);
            double ny = round(y);
            noteFences(state, helmet, position, nx, ny, when);
            JSONArray next = new JSONArray();
            next.add(nx);
            next.add(ny);
            helmet.person.put("position", next);
            helmet.person.put("locationValid", true);
            helmet.person.put("updated", minute(when));
        } else if (position != null) {
            helmet.person.put("locationValid", false);
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
        if (personId == null) return null;
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
            if (work == null || !day.equals(work.getString("date")) || "已结束".equals(work.getString("status"))) continue;
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
