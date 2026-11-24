package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.*;
import okhttp3.Response;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.*;
import java.io.*;
import java.util.*;
import static com.ruoyi.melhat.split.SplitTelemetry.*;

@RestController
@RequestMapping("/api/guardian/v1/split")
public class SplitHelmetSessionController {
    private final SplitHelmetService service;private final PersonEquipmentContext equipment;private final GuardianAccess access;
    public SplitHelmetSessionController(SplitHelmetService service,PersonEquipmentContext equipment,GuardianAccess access){this.service=service;this.equipment=equipment;this.access=access;}
    @ModelAttribute public void headers(HttpServletResponse response){response.setHeader("Cache-Control","no-store, private");}
    private void current(GuardianAccess.Context ctx, JSONObject session, boolean openingMicrophone) {
        boolean preview = "preview".equals(session.getString("mode"));
        boolean monitorTalk = preview && (openingMicrophone || session.getBooleanValue("monitorTalk"));
        for (Object raw : session.getJSONArray("recipients")) {
            JSONObject recipient = (JSONObject) raw;
            String sn = recipient.getString("deviceId");
            if (preview) equipment.require(ctx, sn, recipient, "video", "communications:voice");
            if (!preview || monitorTalk) equipment.require(ctx, sn, recipient, "voice", "communications:voice");
            if (monitorTalk || !preview && session.getBooleanValue("video"))
                equipment.require(ctx, sn, recipient, "videoCall", "communications:voice");
        }
    }
    @PostMapping(value="/sessions/{id}/devices/{sn}/{kind:play|talk}",consumes="application/sdp",produces="application/sdp")
    public String signal(@PathVariable String id,@PathVariable String sn,@PathVariable String kind,@RequestBody String sdp,HttpServletRequest request){
        boolean talking = "talk".equals(kind);
        String actor=equipment.execute(WearableSessions.actor(request),ctx->{
            JSONObject session=service.owned(ctx.id(),id);
            current(ctx,session,talking);
            if(talking && "preview".equals(session.getString("mode"))) service.enableMonitorTalk(ctx.id(),id,sn);
            return ctx.id();
        });
        String answer=service.signal(actor,id,sn,kind,sdp);
        try{equipment.execute(WearableSessions.actor(request),ctx->{JSONObject session=service.owned(ctx.id(),id);current(ctx,session,talking);if(!Arrays.asList("offered","connected").contains(session.getString("status"))||session.getLongValue("expiresMillis")<System.currentTimeMillis())throw fail(409,"CALL_EXPIRED","会话已结束或过期");return true;});}
        catch(RuntimeException revoked){try{service.end(id);}catch(RuntimeException cleanup){revoked.addSuppressed(cleanup);}throw revoked;}
        return answer;
    }
    @PostMapping("/sessions/{id}/heartbeat") public JSONObject heartbeat(@PathVariable String id,HttpServletRequest request){return equipment.execute(WearableSessions.actor(request),ctx->{JSONObject session=service.owned(ctx.id(),id);current(ctx,session,false);return service.heartbeat(ctx.id(),id);});}
    @PostMapping("/sessions/{id}/end") public JSONObject end(@PathVariable String id,HttpServletRequest request){GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));service.owned(ctx.id(),id);service.end(id);return service.callState(id);}
    @GetMapping("/devices/{sn}/files/{id}") public void file(@PathVariable String sn,@PathVariable String id,HttpServletRequest request,HttpServletResponse response)throws IOException{
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));JSONObject context=service.fileContext(sn,id);
        if(!ctx.can("assets:read",context.getString("siteId"),context.getString("areaId")))throw fail(403,"PERMISSION_DENIED","设备文件不在授权范围");
        JSONObject snapshot=service.fileSnapshot(sn,id);
        if(!ctx.can("assets:read",snapshot.getString("siteId"),snapshot.getString("areaId")))throw fail(403,"PERMISSION_DENIED","设备文件历史归属已变化，请刷新后重试");
        try(Response upstream=service.client().file(snapshot.getString("privateSourceUrl"),sn,request.getHeader("Range"))){
            if(upstream.code()!=200&&upstream.code()!=206)throw fail(502,"SPLIT_FILE_UNAVAILABLE","文件暂时无法读取，请刷新目录");
            if(upstream.body()==null)throw fail(502,"SPLIT_FILE_UNAVAILABLE","文件响应无效");
            if(snapshot.get("size")!=null){long expected=snapshot.getLongValue("size"),actual=upstream.body().contentLength();String range=upstream.header("Content-Range");if(upstream.code()==206&&range!=null&&range.matches("bytes [0-9]+-[0-9]+/[0-9]+"))actual=Long.parseLong(range.substring(range.lastIndexOf('/')+1));else if(upstream.code()==206)actual=-1;if(actual>=0&&actual!=expected)throw fail(410,"FILE_REVISION_UNAVAILABLE","文件版本已经变化，请重新查询目录");}
            String modified=upstream.header("Last-Modified");if(modified!=null&&snapshot.getString("createdAt")!=null){try{long received=java.time.ZonedDateTime.parse(modified,java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().getEpochSecond(),expected=java.time.Instant.parse(snapshot.getString("createdAt")).getEpochSecond();if(received!=expected)throw fail(410,"FILE_REVISION_UNAVAILABLE","文件版本已经变化，请重新查询目录");}catch(java.time.format.DateTimeParseException unsupported){/* Directory metadata was verified; no precision is invented from a malformed optional header. */}}
            String type=upstream.header("Content-Type","").split(";",2)[0];if(!Arrays.asList("image/jpeg","image/png","image/webp","video/mp4","audio/mpeg","audio/wav","audio/ogg","application/octet-stream").contains(type))throw fail(502,"SPLIT_FILE_TYPE","文件类型不受支持");
            if("application/octet-stream".equals(type)){String key=String.valueOf(snapshot.get("privateFileKey")).toLowerCase(Locale.ROOT);for(String[] pair:new String[][]{{".jpg","image/jpeg"},{".jpeg","image/jpeg"},{".png","image/png"},{".webp","image/webp"},{".mp4","video/mp4"},{".mp3","audio/mpeg"},{".wav","audio/wav"},{".ogg","audio/ogg"}})if(key.endsWith(pair[0])){type=pair[1];break;}}
            response.setStatus(upstream.code());response.setContentType(type);response.setHeader("X-Content-Type-Options","nosniff");response.setHeader("Content-Disposition","inline");
            for(String h:Arrays.asList("Content-Length","Content-Range","Accept-Ranges")){String value=upstream.header(h);if(value!=null)response.setHeader(h,value);}
            try(InputStream in=upstream.body().byteStream()){byte[]buffer=new byte[16384];for(int n;(n=in.read(buffer))!=-1;)response.getOutputStream().write(buffer,0,n);}
        }
    }
}
