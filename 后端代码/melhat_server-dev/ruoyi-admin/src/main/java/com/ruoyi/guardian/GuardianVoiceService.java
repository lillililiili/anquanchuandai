package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.pojo.param.TtsBroadcastParam;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class GuardianVoiceService {
    private final HeadbandService headband;
    private final ITtsTextSynthesisBroadcastService broadcasts;

    public GuardianVoiceService(HeadbandService headband, ITtsTextSynthesisBroadcastService broadcasts) {
        this.headband = headband;
        this.broadcasts = broadcasts;
    }

    public void broadcast(JSONArray hats, String content) {
        broadcast(hats, content, "legacy", "历史客户端");
    }
    public void broadcast(JSONArray hats, String content, String actorId, String actorName) {
        String text = content == null ? "" : content.trim();
        if (text.isEmpty() || text.length() > 200) throw new GuardianRejected("广播内容需为 1–200 字");
        List<String> numbers = new ArrayList<String>();
        List<String> names = new ArrayList<String>();
        readHats(hats, numbers, names);
        try {
            headband.groupBroadcast(new TtsBroadcastParam(numbers, text));
        } catch (ServiceException error) {
            throw rejected(error);
        } catch (Exception error) {
            throw new GuardianRejected("请求安全帽异常");
        }
        TtsTextSynthesisBroadcast record = new TtsTextSynthesisBroadcast();
        Date now = new Date();
        record.setDelFlag("0");
        record.setBroadcastType(numbers.size() == 1 ? "01" : "02");
        record.setContent(text);
        record.setOperator(actorName);
        record.setCreateBy(actorId);
        record.setUpdateBy(actorId);
        record.setHatNumber(join(numbers));
        record.setRecipient(join(names));
        record.setRecipientCount(numbers.size());
        record.setCreateTime(now);
        record.setSendTime(now);
        if (!broadcasts.save(record)) throw new GuardianRejected("请求安全帽异常");
    }

    public Map<String, Object> call(JSONArray hats) {
        List<String> numbers = new ArrayList<String>();
        readHats(hats, numbers, new ArrayList<String>());
        Map<String, Object> param = new HashMap<String, Object>();
        param.put("helmetSnList", numbers);
        ResponseVO response;
        try {
            response = headband.agoraToken(param);
        } catch (ServiceException error) {
            throw rejected(error);
        } catch (Exception error) {
            throw new GuardianRejected("请求安全帽异常");
        }
        JSONObject data = response.getData() == null ? null : JSONObject.from(response.getData());
        String appId = text(data, "agoraAppId", "appId");
        String channel = text(data, "channelName", "channel");
        String token = text(data, "agoraToken", "token");
        String uid = text(data, "agoraUid", "uid");
        if (appId == null || channel == null || token == null) throw new GuardianRejected("请求安全帽异常");
        Map<String, Object> rtc = new LinkedHashMap<String, Object>();
        rtc.put("appId", appId);
        rtc.put("channel", channel);
        rtc.put("token", token);
        rtc.put("uid", uid);
        return rtc;
    }

    public void end(String channel) {
        if (channel == null || channel.trim().isEmpty()) return;
        try {
            headband.agoraEnd(channel.trim());
        } catch (ServiceException error) {
            throw rejected(error);
        } catch (Exception error) {
            throw new GuardianRejected("请求安全帽异常");
        }
    }

    private static void readHats(JSONArray hats, List<String> numbers, List<String> names) {
        if (hats == null || hats.isEmpty()) throw new GuardianRejected("请选择呼叫人员");
        for (int i = 0; i < hats.size(); i++) {
            JSONObject hat = hats.getJSONObject(i);
            String number = hat == null ? null : hat.getString("hatNumber");
            if (number == null || number.trim().isEmpty()) throw new GuardianRejected("没有领用安全帽");
            numbers.add(number.trim());
            String name = hat.getString("name");
            names.add(name == null ? "" : name);
        }
    }

    private static GuardianRejected rejected(ServiceException error) {
        String message = error.getMessage();
        return new GuardianRejected(message == null || message.trim().isEmpty() ? "请求安全帽异常" : message);
    }

    private static String text(JSONObject data, String first, String second) {
        if (data == null) return null;
        String value = data.getString(first);
        if (value == null || value.trim().isEmpty()) value = data.getString(second);
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }

    private static String join(List<String> values) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) builder.append(",");
            builder.append(values.get(i));
        }
        return builder.toString();
    }
}
