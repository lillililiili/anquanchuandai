package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 只把监护数据里的安全帽对到 safety_hat_info.hat_number。
 * 安全带、手表不进帽子档案。create_by 不是 guardian 的同编号帽子保持原样。
 */
@Service
public class GuardianHatArchive {
    static final String OWNER = "guardian";

    private final SafetyHatInfoMapper mapper;

    public GuardianHatArchive(SafetyHatInfoMapper mapper) {
        this.mapper = mapper;
    }

    @Transactional(rollbackFor = Exception.class)
    public void ensureUnassigned(String number) {
        if (number == null || number.trim().isEmpty() || number.length() > 64) throw new IllegalArgumentException("安全帽编号缺失");
        List<SafetyHatInfo> rows = mapper.findIncludingDeleted(number);
        if (rows.size() > 1) throw new IllegalArgumentException("安全帽编号重复");
        if (!rows.isEmpty()) return;
        SafetyHatInfo hat = new SafetyHatInfo();
        hat.setHatNumber(number);
        hat.setStatus("0");
        hat.setAlarmCount(0);
        hat.setDelFlag("0");
        hat.setCreateBy(OWNER);
        hat.setCreateTime(new Date());
        hat.setUpdateBy(OWNER);
        hat.setUpdateTime(new Date());
        if (mapper.insert(hat) != 1) throw new IllegalStateException("安全帽档案保存失败");
    }

    @Transactional(rollbackFor = Exception.class)
    public void sync(JSONObject state) {
        JSONArray devices = state == null ? null : state.getJSONArray("devices");
        if (devices == null) return;
        Set<String> numbers = new HashSet<String>();
        for (int i = 0; i < devices.size(); i++) {
            JSONObject device = devices.getJSONObject(i);
            if (device == null || !"H".equals(device.getString("type"))) continue;
            String number = device.getString("id");
            if (number == null || number.trim().isEmpty() || number.length() > 64) {
                throw new IllegalArgumentException("安全帽编号缺失");
            }
            if (!numbers.add(number)) throw new IllegalArgumentException("安全帽编号重复");
            upsert(state, device, number);
        }
        retireMissing(numbers);
    }

    private void upsert(JSONObject state, JSONObject device, String number) {
        List<SafetyHatInfo> rows = mapper.findIncludingDeleted(number);
        if (rows.size() > 1) throw new IllegalArgumentException("安全帽编号重复");
        String wearer = wearer(state, number);
        if (wearer != null && wearer.length() > 64) throw new IllegalArgumentException("人员姓名超出安全帽档案长度");
        String status = device.getBooleanValue("active") && device.getBooleanValue("online") ? "1" : "0";
        BigDecimal battery = device.getBigDecimal("battery");
        Date boundAt = wearer == null ? null : parseTime(openBindingStart(state, number));
        if (rows.isEmpty()) {
            SafetyHatInfo hat = new SafetyHatInfo();
            hat.setHatNumber(number);
            hat.setBindUserName(wearer);
            hat.setBindTime(boundAt);
            hat.setStatus(status);
            hat.setElectricityUsage(battery);
            hat.setAlarmCount(0);
            hat.setDelFlag("0");
            hat.setCreateBy(OWNER);
            hat.setCreateTime(new Date());
            hat.setUpdateBy(OWNER);
            hat.setUpdateTime(new Date());
            if (mapper.insert(hat) != 1) throw new IllegalStateException("安全帽档案保存失败");
            return;
        }
        SafetyHatInfo current = rows.get(0);
        if (!OWNER.equals(current.getCreateBy()) || !"0".equals(String.valueOf(current.getDelFlag()))) return;
        apply(current.getId(), wearer, boundAt, status, battery);
    }

    private void apply(Long id, String wearer, Date boundAt, String status, BigDecimal battery) {
        UpdateWrapper<SafetyHatInfo> update = new UpdateWrapper<SafetyHatInfo>();
        update.eq("id", id)
                .set("bind_user_name", wearer)
                .set("bind_time", boundAt)
                .set("status", status)
                .set("electricity_usage", battery)
                .set("update_by", OWNER)
                .set("update_time", new Date());
        if (mapper.update(null, update) != 1) throw new IllegalStateException("安全帽档案保存失败");
    }

    private void retireMissing(Set<String> numbers) {
        QueryWrapper<SafetyHatInfo> query = new QueryWrapper<SafetyHatInfo>();
        query.eq("create_by", OWNER);
        List<SafetyHatInfo> owned = mapper.selectList(query);
        for (int i = 0; i < owned.size(); i++) {
            SafetyHatInfo row = owned.get(i);
            if (numbers.contains(row.getHatNumber())) continue;
            apply(row.getId(), null, null, "0", row.getElectricityUsage());
        }
    }

    private static String wearer(JSONObject state, String deviceId) {
        String personId = null;
        JSONArray bindings = state.getJSONArray("bindings");
        if (bindings != null) {
            for (int i = 0; i < bindings.size(); i++) {
                JSONObject binding = bindings.getJSONObject(i);
                if (binding == null || binding.get("end") != null) continue;
                if (!deviceId.equals(binding.getString("deviceId"))) continue;
                personId = binding.getString("personId");
            }
        }
        if (personId == null) return null;
        JSONArray people = state.getJSONArray("people");
        if (people == null) return null;
        for (int i = 0; i < people.size(); i++) {
            JSONObject person = people.getJSONObject(i);
            if (person != null && personId.equals(person.getString("id"))) return person.getString("name");
        }
        return null;
    }

    private static String openBindingStart(JSONObject state, String deviceId) {
        JSONArray bindings = state.getJSONArray("bindings");
        if (bindings == null) return null;
        for (int i = 0; i < bindings.size(); i++) {
            JSONObject binding = bindings.getJSONObject(i);
            if (binding == null || binding.get("end") != null) continue;
            if (deviceId.equals(binding.getString("deviceId"))) return binding.getString("start");
        }
        return null;
    }

    private static Date parseTime(String text) {
        if (text == null || text.length() < 19) return null;
        try {
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(text.substring(0, 19));
        } catch (ParseException error) {
            return null;
        }
    }
}
