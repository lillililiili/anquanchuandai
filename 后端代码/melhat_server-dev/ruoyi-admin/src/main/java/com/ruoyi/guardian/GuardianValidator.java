package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;

import java.util.HashSet;
import java.util.Set;

public final class GuardianValidator {
    private GuardianValidator() {}

    public static void check(JSONObject state) {
        if (state == null || state.getIntValue("version") != 1) {
            throw new IllegalArgumentException("版本不匹配");
        }
        for (String name : new String[]{"people", "devices", "works", "events", "media", "fences", "groups"}) {
            unique(state.getJSONArray(name));
        }
        JSONArray bindings = state.getJSONArray("bindings");
        JSONArray devices = state.getJSONArray("devices");
        JSONArray people = state.getJSONArray("people");
        Set<String> devicesBound = new HashSet<String>();
        Set<String> personType = new HashSet<String>();
        if (bindings != null) {
            for (int i = 0; i < bindings.size(); i++) {
                JSONObject binding = bindings.getJSONObject(i);
                if (binding.get("end") != null) continue;
                String deviceId = binding.getString("deviceId");
                String personId = binding.getString("personId");
                if (!devicesBound.add(deviceId)) throw new IllegalArgumentException("设备重复绑定");
                if (!personType.add(personId + ":" + deviceType(devices, deviceId))) {
                    throw new IllegalArgumentException("同类设备重复绑定");
                }
                if (!active(people, personId) || !active(devices, deviceId)) {
                    throw new IllegalArgumentException("绑定关系无效");
                }
            }
        }
        checkWorks(state.getJSONArray("works"), people);
        checkFences(state.getJSONArray("fences"));
        checkEvents(state.getJSONArray("events"), state.getJSONArray("media"));
        checkCapturedMedia(state);
        checkDispatch(state);
        checkSos(state);
    }

    private static void checkSos(JSONObject state) {
        JSONObject sos = state.getJSONObject("sos");
        if (sos == null) throw new IllegalArgumentException("记录不存在或已归档");
        JSONArray people = state.getJSONArray("people");
        JSONArray events = state.getJSONArray("events");
        JSONObject event = findById(events, "RL-E-0915-004");
        if (!"RL-E-0915-004".equals(sos.getString("eventId"))
                || !"P8".equals(sos.getString("personId"))
                || !"何平".equals(sos.getString("personName"))
                || !"RL-H008".equals(sos.getString("deviceId"))
                || event == null
                || !"P8".equals(event.getString("personId"))
                || !"RL-H008".equals(event.getString("deviceId"))
                || !"人员求助".equals(event.getString("type"))) {
            throw new IllegalArgumentException("SOS协助与告警不一致");
        }
        String status = sos.getString("status");
        if (!allowed(status, "waiting", "active", "ended")) throw new IllegalArgumentException("本次协助已结束");
        JSONArray members = sos.getJSONArray("members");
        int operators = 0;
        if (members != null) {
            for (int i = 0; i < members.size(); i++) {
                String id = members.getString(i);
                if ("operator".equals(id)) {
                    operators++;
                    continue;
                }
                if (!active(people, id) || !sameStation(people, id, sos.getString("station"))) {
                    throw new IllegalArgumentException("呼叫人员无效");
                }
            }
        }
        if (operators > 1 || ("waiting".equals(status) && operators > 0) || ("active".equals(status) && operators != 1)) {
            throw new IllegalArgumentException("值守员已经加入");
        }
        boolean joined = timelineHas(sos, "值守员加入协助（模拟）");
        boolean closed = timelineHas(sos, "协助结束，记录已保存");
        if ("waiting".equals(status) && (joined || closed)) throw new IllegalArgumentException("本次协助已结束");
        if ("active".equals(status) && !joined) throw new IllegalArgumentException("值守员已经加入");
        if ("ended".equals(status) && !closed) throw new IllegalArgumentException("本次协助已结束");
        if (!"ended".equals(status)) return;
        JSONArray calls = state.getJSONArray("calls");
        if (calls == null) throw new IllegalArgumentException("记录不存在或已归档");
        for (int i = 0; i < calls.size(); i++) {
            JSONObject call = calls.getJSONObject(i);
            if (call == null || !"SOS协助".equals(call.getString("kind"))) continue;
            JSONArray callMembers = call.getJSONArray("members");
            if (callMembers == null || !callMembers.contains("P8")) continue;
            if (members != null) {
                boolean complete = true;
                for (int j = 0; j < members.size(); j++) {
                    if (!callMembers.contains(members.getString(j))) complete = false;
                }
                if (!complete) continue;
            }
            return;
        }
        throw new IllegalArgumentException("记录不存在或已归档");
    }

    private static boolean timelineHas(JSONObject sos, String text) {
        JSONArray timeline = sos.getJSONArray("timeline");
        if (timeline == null) return false;
        for (int i = 0; i < timeline.size(); i++) {
            JSONObject item = timeline.getJSONObject(i);
            if (item != null && text.equals(item.getString("text"))) return true;
        }
        return false;
    }

    private static void checkDispatch(JSONObject state) {
        JSONArray people = state.getJSONArray("people");
        JSONArray groups = state.getJSONArray("groups");
        if (groups != null) {
            for (int i = 0; i < groups.size(); i++) {
                JSONObject group = groups.getJSONObject(i);
                if (group == null) continue;
                String name = group.getString("name");
                if (name == null || name.trim().isEmpty()) throw new IllegalArgumentException("请填写分组名称");
                JSONArray members = group.getJSONArray("members");
                if (members == null || members.isEmpty()) throw new IllegalArgumentException("请选择成员");
                Set<String> seen = new HashSet<String>();
                String station = group.getString("station");
                for (int j = 0; j < members.size(); j++) {
                    String id = members.getString(j);
                    if (!seen.add(id) || !active(people, id) || !sameStation(people, id, station)) {
                        throw new IllegalArgumentException("成员不属于当前厂站");
                    }
                }
            }
        }
        JSONArray calls = state.getJSONArray("calls");
        int openCalls = 0;
        if (calls != null) {
            for (int i = 0; i < calls.size(); i++) {
                JSONObject call = calls.getJSONObject(i);
                if (call == null) continue;
                String status = call.getString("status");
                if (!allowed(status, "正在呼叫", "通话中", "已结束")) throw new IllegalArgumentException("通话已经结束");
                if (!"已结束".equals(status)) openCalls++;
                JSONArray members = call.getJSONArray("members");
                if (members == null || members.isEmpty()) throw new IllegalArgumentException("请选择呼叫人员");
                if ("单呼".equals(call.getString("kind")) && members.size() != 1) {
                    throw new IllegalArgumentException("单呼只能选择一人");
                }
                Set<String> memberIds = new HashSet<String>();
                String station = call.getString("station");
                boolean sosCall = "SOS协助".equals(call.getString("kind"));
                if (sosCall && !"已结束".equals(status)) throw new IllegalArgumentException("通话已经结束");
                for (int j = 0; j < members.size(); j++) {
                    String id = members.getString(j);
                    if ("operator".equals(id)) {
                        if (!sosCall || !memberIds.add(id)) throw new IllegalArgumentException("呼叫人员无效");
                        continue;
                    }
                    if (!memberIds.add(id) || !active(people, id) || !sameStation(people, id, station)) {
                        throw new IllegalArgumentException("呼叫人员无效");
                    }
                }
                if ("通话中".equals(status)) {
                    JSONArray joined = call.getJSONArray("joined");
                    if (joined == null || joined.size() != memberIds.size()) throw new IllegalArgumentException("呼叫人员无效");
                    for (int j = 0; j < joined.size(); j++) {
                        if (!memberIds.contains(joined.getString(j))) throw new IllegalArgumentException("呼叫人员无效");
                    }
                }
            }
        }
        if (openCalls > 1) throw new IllegalArgumentException("请先结束当前通话");
        JSONArray broadcasts = state.getJSONArray("broadcasts");
        if (broadcasts == null) return;
        for (int i = 0; i < broadcasts.size(); i++) {
            JSONObject item = broadcasts.getJSONObject(i);
            if (item == null) continue;
            String text = item.getString("text");
            if (text == null || text.trim().isEmpty() || text.length() > 200) {
                throw new IllegalArgumentException("广播内容需为 1–200 字");
            }
            if (findById(groups, item.getString("groupId")) == null) {
                throw new IllegalArgumentException("记录不存在或已归档");
            }
        }
    }

    private static void checkCapturedMedia(JSONObject state) {
        JSONArray media = state.getJSONArray("media");
        if (media == null) return;
        JSONArray people = state.getJSONArray("people");
        JSONArray devices = state.getJSONArray("devices");
        JSONArray bindings = state.getJSONArray("bindings");
        JSONArray works = state.getJSONArray("works");
        for (int i = 0; i < media.size(); i++) {
            JSONObject item = media.getJSONObject(i);
            if (item == null) continue;
            String source = item.getString("source");
            if (!"手动抓拍".equals(source) && !"手动录像（图片模拟）".equals(source)) continue;
            String personId = item.getString("personId");
            JSONObject person = findById(people, personId);
            if (person == null) throw new IllegalArgumentException("资料人员无效");
            String station = item.getString("station");
            if (station == null || !station.equals(person.getString("station"))) {
                throw new IllegalArgumentException("资料与人员厂站不一致");
            }
            if (!openHelmet(bindings, devices, personId, item.getString("deviceId"))) {
                throw new IllegalArgumentException("该人员未绑定安全帽");
            }
            String workId = item.getString("workId");
            if (workId != null && !workId.isEmpty() && !workIncludes(works, workId, personId)) {
                throw new IllegalArgumentException("资料与作业人员不一致");
            }
            String kind = item.getString("kind");
            if ("手动抓拍".equals(source) && !"photo".equals(kind)) throw new IllegalArgumentException("资料类型无效");
            if ("手动录像（图片模拟）".equals(source) && !"video".equals(kind)) throw new IllegalArgumentException("资料类型无效");
            if (item.getIntValue("duration") < 1) throw new IllegalArgumentException("资料时长无效");
            JSONObject snapshot = item.getJSONObject("snapshot");
            String personName = snapshot == null ? null : snapshot.getString("personName");
            if (personName == null || personName.trim().isEmpty()) throw new IllegalArgumentException("资料人员无效");
        }
    }

    private static boolean openHelmet(JSONArray bindings, JSONArray devices, String personId, String deviceId) {
        if (bindings == null || personId == null || deviceId == null) return false;
        if (!"H".equals(deviceType(devices, deviceId)) || !active(devices, deviceId)) return false;
        for (int i = 0; i < bindings.size(); i++) {
            JSONObject binding = bindings.getJSONObject(i);
            if (binding == null || binding.get("end") != null) continue;
            if (personId.equals(binding.getString("personId")) && deviceId.equals(binding.getString("deviceId"))) return true;
        }
        return false;
    }

    private static boolean workIncludes(JSONArray works, String workId, String personId) {
        JSONObject work = findById(works, workId);
        if (work == null) return false;
        JSONArray members = work.getJSONArray("members");
        if (members == null) return false;
        for (int i = 0; i < members.size(); i++) {
            if (personId.equals(members.getString(i))) return true;
        }
        return false;
    }

    private static JSONObject findById(JSONArray list, String id) {
        if (list == null || id == null) return null;
        for (int i = 0; i < list.size(); i++) {
            JSONObject item = list.getJSONObject(i);
            if (item != null && id.equals(item.getString("id"))) return item;
        }
        return null;
    }

    private static void checkEvents(JSONArray events, JSONArray media) {
        Set<String> eventIds = new HashSet<String>();
        if (events != null) {
            for (int i = 0; i < events.size(); i++) {
                JSONObject event = events.getJSONObject(i);
                if (event == null) continue;
                String id = event.getString("id");
                if (id != null) eventIds.add(id);
                String status = event.getString("status");
                if (!allowed(status, "待现场核验", "待认领", "处理中", "已核验")) {
                    throw new IllegalArgumentException("事件状态无效");
                }
                JSONObject verification = event.getJSONObject("verification");
                if ("已核验".equals(status)) {
                    checkVerificationText(verification, true);
                } else if (verification != null) {
                    throw new IllegalArgumentException("核验记录与事件状态不一致");
                }
                checkVerificationText(event.getJSONObject("draft"), false);
            }
        }
        if (media == null) return;
        for (int i = 0; i < media.size(); i++) {
            JSONObject item = media.getJSONObject(i);
            if (item == null || !"核验上传".equals(item.getString("source"))) continue;
            String eventId = item.getString("eventId");
            if (eventId == null || !eventIds.contains(eventId)) {
                throw new IllegalArgumentException("核验照片未关联事件");
            }
        }
    }

    private static void checkVerificationText(JSONObject form, boolean required) {
        if (form == null) {
            if (required) throw new IllegalArgumentException("请选择核验结论并填写现场情况");
            return;
        }
        String situation = form.getString("situation");
        String measures = form.getString("measures");
        if ((situation != null && situation.length() > 500) || (measures != null && measures.length() > 500)) {
            throw new IllegalArgumentException("填写内容不能超过 500 字");
        }
        if (!required) return;
        String conclusion = form.getString("conclusion");
        if (!allowed(conclusion, "设备通信异常", "需现场处理", "暂无法确认")
                || situation == null || situation.trim().isEmpty()) {
            throw new IllegalArgumentException("请选择核验结论并填写现场情况");
        }
    }

    private static boolean allowed(String value, String... options) {
        if (value == null) return false;
        for (int i = 0; i < options.length; i++) {
            if (value.equals(options[i])) return true;
        }
        return false;
    }

    private static void checkFences(JSONArray fences) {
        if (fences == null) return;
        for (int i = 0; i < fences.size(); i++) {
            JSONObject fence = fences.getJSONObject(i);
            if (fence == null) continue;
            String name = fence.getString("name");
            if (name == null || name.trim().isEmpty()) throw new IllegalArgumentException("请填写围栏名称");
            JSONArray points = fence.getJSONArray("points");
            if (points == null || points.size() < 3) throw new IllegalArgumentException("围栏至少需要 3 个节点");
            if (polygonArea(points) < 1) throw new IllegalArgumentException("围栏区域过小");
            if (selfIntersects(points)) throw new IllegalArgumentException("围栏边界不能交叉");
        }
    }

    private static double polygonArea(JSONArray points) {
        double value = 0;
        int count = points.size();
        for (int i = 0; i < count; i++) {
            double x1 = coord(points, i, 0);
            double y1 = coord(points, i, 1);
            double x2 = coord(points, (i + 1) % count, 0);
            double y2 = coord(points, (i + 1) % count, 1);
            value += x1 * y2 - x2 * y1;
        }
        return Math.abs(value / 2);
    }

    private static boolean selfIntersects(JSONArray points) {
        int count = points.size();
        for (int i = 0; i < count; i++) {
            for (int j = i + 2; j < count; j++) {
                if (i == 0 && j == count - 1) continue;
                double ab = edgeCross(points, i, j);
                double cd = edgeCross(points, j, i);
                if (ab < 0 && cd < 0) return true;
            }
        }
        return false;
    }

    private static double edgeCross(JSONArray points, int edge, int other) {
        int count = points.size();
        double ax = coord(points, edge, 0);
        double ay = coord(points, edge, 1);
        double bx = coord(points, (edge + 1) % count, 0);
        double by = coord(points, (edge + 1) % count, 1);
        double c1 = cross(ax, ay, bx, by, coord(points, other, 0), coord(points, other, 1));
        double c2 = cross(ax, ay, bx, by, coord(points, (other + 1) % count, 0), coord(points, (other + 1) % count, 1));
        return c1 * c2;
    }

    private static double cross(double ax, double ay, double bx, double by, double cx, double cy) {
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    }

    private static double coord(JSONArray points, int index, int axis) {
        JSONArray point = points.getJSONArray(index);
        if (point == null || point.size() < 2) throw new IllegalArgumentException("围栏至少需要 3 个节点");
        return point.getDoubleValue(axis);
    }

    private static void checkWorks(JSONArray works, JSONArray people) {
        if (works == null) return;
        Set<String> assigned = new HashSet<String>();
        for (int i = 0; i < works.size(); i++) {
            JSONObject work = works.getJSONObject(i);
            if (work == null) continue;
            String start = work.getString("start");
            String end = work.getString("end");
            if (start != null && !start.isEmpty() && end != null && !end.isEmpty() && start.compareTo(end) >= 0) {
                throw new IllegalArgumentException("结束时间必须晚于开始时间");
            }
            JSONArray members = work.getJSONArray("members");
            if (members == null) continue;
            Set<String> seen = new HashSet<String>();
            boolean current = !"已结束".equals(work.getString("status"));
            String date = work.getString("date");
            String station = work.getString("station");
            for (int j = 0; j < members.size(); j++) {
                String id = members.getString(j);
                if (!seen.add(id) || !active(people, id) || !sameStation(people, id, station)) {
                    throw new IllegalArgumentException("作业成员无效");
                }
                if (current && !assigned.add(String.valueOf(date) + "\n" + id)) {
                    throw new IllegalArgumentException(personName(people, id) + " 已参加其他作业");
                }
            }
        }
    }

    private static void unique(JSONArray list) {
        if (list == null) return;
        Set<String> seen = new HashSet<String>();
        for (int i = 0; i < list.size(); i++) {
            if (!seen.add(list.getJSONObject(i).getString("id"))) throw new IllegalArgumentException("重复记录 ID");
        }
    }

    private static boolean sameStation(JSONArray people, String id, String station) {
        if (people == null || id == null) return false;
        for (int i = 0; i < people.size(); i++) {
            JSONObject person = people.getJSONObject(i);
            if (person == null || !id.equals(person.getString("id"))) continue;
            String theirs = person.getString("station");
            return station == null ? theirs == null : station.equals(theirs);
        }
        return false;
    }

    private static String personName(JSONArray people, String id) {
        if (people == null || id == null) return "";
        for (int i = 0; i < people.size(); i++) {
            JSONObject person = people.getJSONObject(i);
            if (person != null && id.equals(person.getString("id"))) {
                String name = person.getString("name");
                return name == null || name.isEmpty() ? id : name;
            }
        }
        return id;
    }

    private static boolean active(JSONArray list, String id) {
        if (list == null || id == null) return false;
        for (int i = 0; i < list.size(); i++) {
            JSONObject item = list.getJSONObject(i);
            if (id.equals(item.getString("id")) && item.getBooleanValue("active")) return true;
        }
        return false;
    }

    private static String deviceType(JSONArray devices, String id) {
        if (devices == null) return "";
        for (int i = 0; i < devices.size(); i++) {
            JSONObject device = devices.getJSONObject(i);
            if (id.equals(device.getString("id"))) return String.valueOf(device.getString("type"));
        }
        return "";
    }
}
