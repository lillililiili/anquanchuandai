package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.HelmetMediaService;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Device-originated recorded speech. No phone call, automatic playback or read receipt. */
@RestController
@RequestMapping("/api/guardian/v1/voice-messages")
public class GuardianDeviceVoiceMessages {
    private final GuardianStore store;
    private final GuardianAccess access;
    private final HelmetMediaService media;
    public GuardianDeviceVoiceMessages(GuardianStore store,GuardianAccess access,HelmetMediaService media){this.store=store;this.access=access;this.media=media;}
    @ModelAttribute public void privateResponses(HttpServletResponse response){response.setHeader("Cache-Control","no-store, private");response.setHeader("Pragma","no-cache");}

    public String reference(String message){return media.audioReference(message);}
    private static String messageId(String deviceId,String assetId){return "VM-"+org.apache.commons.codec.digest.DigestUtils.sha256Hex(deviceId+"\n"+assetId);}
    public boolean alreadyReceived(String deviceId,String assetId){return find(store.snapshot(),"sharedCommunications",messageId(deviceId,assetId))!=null;}
    /** Resolve remote metadata before the journal transaction/business lock. */
    public JSONObject prepare(String deviceId,String assetId){
        try {JSONObject asset=media.deviceAudioAsset(deviceId,assetId),result=object("status","READY","assetId",assetId,
                "playable",media.deviceAudioPlayback(asset)!=null,"originalMime",asset.get("originalMime"),"playbackMime",asset.get("playbackMime"));
            Number duration=asset.get("durationSeconds") instanceof Number?(Number)asset.get("durationSeconds"):null;
            if(duration!=null&&Double.isFinite(duration.doubleValue())&&duration.doubleValue()>0)result.put("durationSeconds",duration);
            return result;
        }catch(IllegalArgumentException invalid){return object("status","REJECTED","playable",false,"errorCode","AUDIO_ASSET_UNVERIFIED");}
    }
    public void accept(String deviceId,String assetId,JSONObject captured,JSONObject prepared){
        if(captured==null||captured.getString("receivedAt")==null)throw new IllegalArgumentException("语音消息缺少原接收上下文");
        String at=Instant.parse(captured.getString("receivedAt")).toString();
        String id=messageId(deviceId,assetId);
        store.update(state->{
            if(find(state,"sharedCommunications",id)!=null)return false; // Same uploaded recording never changes owner on retransmission.
            JSONObject row=object("id",id,"operationType","deviceVoiceMessage","direction","DEVICE_TO_PLATFORM","source","DIRECT_HELMET",
                    "reportAct","ca_sending_message","deviceId",deviceId,"receivedAt",at,"timeBasis","RECEIVED_AT","version",1,
                    "personId",captured.get("personId"),"personName",captured.get("personName"),"siteId",captured.get("siteId"),"areaId",captured.get("areaId"),
                    "bindingId",captured.get("bindingEnd")==null?captured.get("bindingId"):null,"unassigned",text(captured,"personId").isEmpty());
            for(String key:Arrays.asList("status","assetId","playable","originalMime","playbackMime","durationSeconds","errorCode"))
                if(prepared.containsKey(key))row.put(key,prepared.get(key));
            rows(state,"sharedCommunications").add(0,row);state.put("seq",state.getIntValue("seq")+1);return true;
        });
    }
    public static boolean visible(GuardianAccess.Context ctx,JSONObject row){
        String site=row.getString("siteId"),area=row.getString("areaId");
        if(site==null||site.isEmpty())return "demo-system".equals(ctx.id());
        return ctx.can("communications:voice",site,area)||(ctx.personId()!=null&&ctx.personId().equals(row.getString("personId"))&&ctx.can("self:read",site,area));
    }
    static JSONObject publicRow(JSONObject row){
        JSONObject out=new JSONObject();
        for(String key:Arrays.asList("id","operationType","direction","source","reportAct","deviceId","personId","personName","siteId","bindingId","receivedAt","timeBasis",
                "status","assetId","playable","durationSeconds","originalMime","playbackMime","errorCode","unassigned","version"))
            if(row.containsKey(key))out.put(key,row.get(key));
        return out;
    }
    @GetMapping public JSONObject list(@RequestParam(required=false)String siteId,@RequestParam(required=false)String deviceId,@RequestParam(required=false)String personId,
            @RequestParam(defaultValue="1")int pageNum,@RequestParam(defaultValue="20")int pageSize,HttpServletRequest request){
        if(pageNum<1||pageSize<1||pageSize>100)throw AdminQueryService.fail(400,"INVALID_PAGE","分页参数无效");
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));
        if(siteId!=null&&!ctx.site(siteId))throw AdminQueryService.fail(403,"PERMISSION_DENIED","厂站不在授权范围");
        List<JSONObject> items=new ArrayList<>();
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){JSONObject row=(JSONObject)raw;
            if("deviceVoiceMessage".equals(row.getString("operationType"))&&visible(ctx,row)
                    &&(siteId==null||siteId.equals(row.getString("siteId")))&&(deviceId==null||deviceId.equals(row.getString("deviceId")))
                    &&(personId==null||personId.equals(row.getString("personId"))))items.add(publicRow(row));}
        items.sort(Comparator.comparing((JSONObject row)->Instant.parse(row.getString("receivedAt"))).reversed().thenComparing(row->row.getString("id")));
        long start=(long)(pageNum-1)*pageSize;
        return object("rows",start>=items.size()?Collections.emptyList():items.subList((int)start,Math.min((int)start+pageSize,items.size())),"total",items.size(),"pageNum",pageNum,"pageSize",pageSize);
    }
    @GetMapping("/{id}/playback") public JSONObject playback(@PathVariable String id,HttpServletRequest request){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));JSONObject row=find(store.snapshot(),"sharedCommunications",id);
        if(row==null||!"deviceVoiceMessage".equals(row.getString("operationType"))||!visible(ctx,row))throw AdminQueryService.fail(404,"VOICE_MESSAGE_NOT_FOUND","语音消息不存在或不在授权范围");
        if(!"READY".equals(row.getString("status"))||text(row,"assetId").isEmpty())throw AdminQueryService.fail(404,"AUDIO_ASSET_UNVERIFIED","此消息没有已核实的录音文件");
        try {JSONObject asset=media.deviceAudioAsset(row.getString("deviceId"),row.getString("assetId")),ticket=media.deviceAudioPlayback(asset);
            if(ticket==null)throw AdminQueryService.fail(503,"AUDIO_PLAYBACK_UNAVAILABLE","录音播放副本暂不可用");
            if(!visible(access.context(WearableSessions.actor(request)),row))throw AdminQueryService.fail(404,"VOICE_MESSAGE_NOT_FOUND","语音消息不在授权范围");
            ticket.put("id",id);return ticket;
        }catch(IllegalArgumentException invalid){throw AdminQueryService.fail(404,"AUDIO_ASSET_UNVERIFIED","录音文件不存在或来源不符");}
        catch(IllegalStateException unavailable){throw AdminQueryService.fail(503,"MEDIA_SERVICE_UNAVAILABLE","音频服务暂不可用");}
    }
}
