package com.ruoyi.wear.call;

import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.headband.pojo.param.TtsSingleBroadcastParam;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.wear.call.dto.CallCredentialsDto;

@Service
public class CallGateway
{
    @Value("${melhat.demo-mode:false}")
    private boolean demoMode;

    @Autowired(required = false)
    private HeadbandService headbandService;

    public boolean isDemoMode()
    {
        return demoMode;
    }

    public CallCredentialsDto issue(Long callId, Long userId, String sn, boolean video)
    {
        if (demoMode || headbandService == null)
        {
            CallCredentialsDto demo = new CallCredentialsDto();
            demo.setAgoraAppId("demo");
            demo.setChannelName("wear-demo-" + callId);
            demo.setAgoraUid(userId == null ? "0" : String.valueOf(userId));
            demo.setAgoraToken("demo-token");
            demo.setExpiresAt(new Date(System.currentTimeMillis() + 3600_000L));
            demo.setDemo(Boolean.TRUE);
            demo.setVideo(Boolean.valueOf(video));
            return demo;
        }
        try
        {
            Map<String, Object> param = new HashMap<String, Object>();
            param.put("helmetSnList", Collections.singletonList(sn));
            ResponseVO vo = headbandService.agoraToken(param);
            Object data = vo == null ? null : vo.getData();
            CallCredentialsDto cred = parse(data, video);
            cred.setDemo(Boolean.FALSE);
            return cred;
        }
        catch (Exception ex)
        {
            throw new IllegalStateException(ex.getMessage() == null ? "厂商不可达，通话未建立" : ex.getMessage(), ex);
        }
    }

    public void endChannel(String channelName)
    {
        if (demoMode || headbandService == null || StringUtils.isEmpty(channelName))
        {
            return;
        }
        try
        {
            headbandService.agoraEnd(channelName);
        }
        catch (Exception ignored)
        {
        }
    }

    public void endDevice(String sn)
    {
        if (demoMode || headbandService == null || StringUtils.isEmpty(sn))
        {
            return;
        }
        try
        {
            headbandService.endCall(sn);
        }
        catch (Exception ignored)
        {
        }
    }

    public boolean sendTts(String sn, String text)
    {
        if (demoMode || headbandService == null)
        {
            return false;
        }
        try
        {
            TtsSingleBroadcastParam param = new TtsSingleBroadcastParam();
            param.setTargetHelmetId(sn);
            param.setContent(text);
            ResponseVO vo = headbandService.singleBroadcast(param);
            return vo != null && vo.getCode() == 200;
        }
        catch (Exception ex)
        {
            throw new IllegalStateException(ex.getMessage() == null ? "厂商不可达" : ex.getMessage(), ex);
        }
    }

    @SuppressWarnings("unchecked")
    private CallCredentialsDto parse(Object data, boolean video)
    {
        CallCredentialsDto cred = new CallCredentialsDto();
        cred.setVideo(Boolean.valueOf(video));
        cred.setExpiresAt(new Date(System.currentTimeMillis() + 3600_000L));
        if (!(data instanceof Map))
        {
            throw new IllegalStateException("厂商不可达，通话未建立");
        }
        Map<String, Object> map = (Map<String, Object>) data;
        cred.setAgoraAppId(str(first(map, "agoraAppId", "appId")));
        cred.setChannelName(str(first(map, "channelName", "channel")));
        cred.setAgoraUid(str(first(map, "agoraUid", "uid")));
        cred.setAgoraToken(str(first(map, "agoraToken", "token")));
        if (StringUtils.isEmpty(cred.getChannelName()) || StringUtils.isEmpty(cred.getAgoraToken()))
        {
            throw new IllegalStateException("厂商不可达，通话未建立");
        }
        return cred;
    }

    private Object first(Map<String, Object> map, String a, String b)
    {
        if (map.get(a) != null)
        {
            return map.get(a);
        }
        return map.get(b);
    }

    private String str(Object value)
    {
        return value == null ? null : String.valueOf(value);
    }
}
