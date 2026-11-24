package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.annotation.Anonymous;
import com.ruoyi.guardian.AdminQueryService;
import com.ruoyi.guardian.WearableMaintenance;
import com.fasterxml.jackson.core.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import static com.ruoyi.melhat.split.SplitTelemetry.*;

/** Only these six service-authenticated callbacks are anonymous to the human login filter. */
@Anonymous
@RestController
@RequestMapping("/api/helmet/notify")
public class SplitHelmetCallbackController {
    private final SplitHelmetProperties properties;private final SplitHelmetService service;
    @Autowired(required=false)private WearableMaintenance maintenance;
    public SplitHelmetCallbackController(SplitHelmetProperties p,SplitHelmetService s){properties=p;service=s;}
    @PostMapping({"/gnss","/baro","/deviceStatus","/sosCall","/sosCallEnd","/sos"})
    public JSONObject accept(@RequestBody String body,HttpServletRequest request){
        if(!properties.isEnabled())throw fail(503,"SPLIT_DISABLED","分体帽接入未启用");
        String supplied=request.getHeader("X-Helmet-Callback-Secret");
        if(supplied==null||properties.getCallbackSecret().length()<32||!MessageDigest.isEqual(properties.getCallbackSecret().getBytes(StandardCharsets.UTF_8),supplied.getBytes(StandardCharsets.UTF_8)))throw fail(401,"CALLBACK_UNAUTHORIZED","回调认证失败");
        if(body==null||body.getBytes(StandardCharsets.UTF_8).length>65536)throw fail(413,"CALLBACK_TOO_LARGE","回调内容过大");
        validateJson(body);
        if(maintenance!=null&&!maintenance.tryBeginWrite())throw fail(503,"MAINTENANCE_PAUSED","业务维护中，请稍后重试");
        try{return service.receive(request.getRequestURI().substring(request.getRequestURI().lastIndexOf('/')+1),JSONObject.parseObject(body),request.getHeader("X-Split-Ingress-Id"),request.getHeader("X-Split-Received-At"));}
        finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private void validateJson(String body){try(JsonParser p=new JsonFactory().enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION).createParser(body)){if(p.nextToken()!=JsonToken.START_OBJECT)throw new IllegalArgumentException();int depth=1;for(JsonToken t;(t=p.nextToken())!=null;){if(t==JsonToken.START_OBJECT||t==JsonToken.START_ARRAY)depth++;if(t==JsonToken.END_OBJECT||t==JsonToken.END_ARRAY)depth--;if(depth>12)throw new IllegalArgumentException();if(depth==0){if(p.nextToken()!=null)throw new IllegalArgumentException();return;}}throw new IllegalArgumentException();}catch(Exception bad){throw fail(400,"CALLBACK_INVALID_JSON","回调JSON格式无效");}}
    @ExceptionHandler(AdminQueryService.QueryFailed.class)
    public ResponseEntity<JSONObject> rejected(AdminQueryService.QueryFailed error){return ResponseEntity.status(error.code).header("Cache-Control","no-store").body(obj("code",error.code,"errorCode",error.errorCode,"message",error.getMessage()));}
}
