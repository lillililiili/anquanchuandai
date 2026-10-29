package com.ruoyi.fuda.gb;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.HelmetCloudClient;
import com.ruoyi.melhat.direct.HelmetMediaService;
import com.ruoyi.guardian.WearableMaintenance;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;

/** Private machine-only API. Network access must additionally be restricted to the GB bridge. */
@RestController
@RequestMapping("/internal/fuda-gb/v1")
public class FudaGbInternalController {
    private final HelmetMediaService media;
    private final WearableMaintenance maintenance;
    private final boolean enabled;
    private final String secret;
    private final Set<String> allowed;
    private final Map<String,Long> nonces=new HashMap<>();
    public FudaGbInternalController(HelmetMediaService media,
            @Value("${fuda.gb.internal-enabled:false}") boolean enabled,
            @Value("${fuda.gb.internal-secret:}") String secret,
            @Value("${fuda.gb.allowed-devices:}") String devices,
            WearableMaintenance maintenance){
        this.media=media;this.enabled=enabled;this.secret=secret;this.maintenance=Objects.requireNonNull(maintenance,"maintenance");
        allowed=new HashSet<>();for(String d:devices.split(","))if(!d.trim().isEmpty())allowed.add(d.trim());
        if(enabled&&(secret.length()<32||allowed.isEmpty()))throw new IllegalArgumentException("GB internal service requires secret and helmet allowlist");
    }
    private synchronized boolean authenticate(HttpServletRequest request,String body){
        if(!enabled)return false;
        String time=request.getHeader("X-GB-Time"),nonce=request.getHeader("X-GB-Nonce"),sig=request.getHeader("X-GB-Signature");
        if(time==null||!time.matches("[0-9]{10}")||nonce==null||!nonce.matches("[A-Za-z0-9_-]{16,100}")||sig==null||!sig.matches("[a-f0-9]{64}"))return false;
        long now=Instant.now().getEpochSecond();if(Math.abs(now-Long.parseLong(time))>60)return false;
        nonces.entrySet().removeIf(e->e.getValue()<now);
        if(nonces.containsKey(nonce)||nonces.size()>10000||request.getQueryString()!=null||body.length()>4096)return false;
        try{String expected=HelmetCloudClient.signature(secret,time,nonce,request.getMethod(),request.getRequestURI(),body.getBytes(StandardCharsets.UTF_8));
            if(!MessageDigest.isEqual(expected.getBytes(StandardCharsets.US_ASCII),sig.getBytes(StandardCharsets.US_ASCII)))return false;
            nonces.put(nonce,now+120);return true;
        }catch(Exception ignored){return false;}
    }
    @RequestMapping(value="/devices/{deviceId}/status",method=RequestMethod.GET)
    public ResponseEntity<JSONObject> status(@PathVariable String deviceId,HttpServletRequest request){
        if(!authenticate(request,""))return error(401,"GB_UNAUTHORIZED");
        if(!allowed.contains(deviceId))return error(404,"GB_HELMET_NOT_FOUND");
        try{return ok(media.gbDeviceStatus(deviceId));}catch(IllegalArgumentException e){return error(404,"GB_HELMET_NOT_FOUND");}catch(Exception e){return error(503,"GB_MEDIA_UNAVAILABLE");}
    }
    @RequestMapping(value="/leases/{leaseId}",method={RequestMethod.PUT,RequestMethod.GET,RequestMethod.DELETE})
    public ResponseEntity<JSONObject> lease(@PathVariable String leaseId,@RequestBody(required=false) String raw,HttpServletRequest request){
        String body=raw==null?"":raw;
        if(!authenticate(request,body))return error(401,"GB_UNAUTHORIZED");
        if(!leaseId.matches("[A-Za-z0-9_-]{16,100}"))return error(400,"GB_INVALID_LEASE");
        // GET can expire/release a lease too. Join the maintenance drain before
        // entering the media monitor, and retain the lease through every outcome.
        if(!maintenance.tryBeginWrite())return error(503,"GB_MAINTENANCE_PAUSED");
        try{
            if("DELETE".equals(request.getMethod()))return ok(media.gbRelease(leaseId));
            if("GET".equals(request.getMethod()))return ok(media.gbLeaseStatus(leaseId));
            JSONObject input=JSON.parseObject(body);String device=input==null?null:input.getString("deviceId");
            if(!allowed.contains(device))return error(404,"GB_HELMET_NOT_FOUND");
            return ok(media.gbAcquire(leaseId,device,90));
        }catch(IllegalArgumentException e){return error(400,"GB_INVALID_REQUEST");}
        catch(IllegalStateException e){String c=e.getMessage();return error("GB_DEVICE_BUSY".equals(c)?409:503,c!=null&&c.matches("GB_[A-Z_]+")?c:"GB_MEDIA_UNAVAILABLE");}
        finally{maintenance.endWrite();}
    }
    private static ResponseEntity<JSONObject> ok(JSONObject data){JSONObject result=new JSONObject();result.put("code",200);result.put("data",data);return ResponseEntity.ok().header("Cache-Control","no-store").body(result);}
    private static ResponseEntity<JSONObject> error(int code,String error){JSONObject result=new JSONObject();result.put("code",code);result.put("error",error);return ResponseEntity.status(code).header("Cache-Control","no-store").body(result);}
}
