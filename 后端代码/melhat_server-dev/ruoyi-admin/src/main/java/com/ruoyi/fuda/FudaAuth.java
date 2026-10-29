package com.ruoyi.fuda;

import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Qualifier;
import javax.servlet.http.HttpServletRequest;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.*;

@Service
public class FudaAuth {
    private final FudaProperties properties; private final FudaNonceStore nonces; private final Clock clock;
    public FudaAuth(FudaProperties properties,FudaNonceStore nonces,@Qualifier("fudaClock") Clock clock){this.properties=properties;this.nonces=nonces;this.clock=clock;}
    public Principal authenticate(HttpServletRequest request,byte[] body){
        if(!properties.isEnabled())throw new FudaException(503,50302,"Fuda API is disabled");
        if(!"POST".equals(request.getMethod())||request.getQueryString()!=null)throw FudaException.bad("POST without query parameters required");
        if(!Arrays.asList("/openapi/wearables/v2/positions/query","/openapi/wearables/v2/statuses/query","/openapi/wearables/v2/alarms/query").contains(request.getRequestURI()))throw new FudaException(404,40401,"Route not allowed");
        if(request.getHeader("Authorization")!=null||request.getHeader("X-Wearable-Token")!=null)throw new FudaException(401,40101,"Human session credentials are not accepted");
        if(properties.getSourcePlatform()==null||properties.getSourcePlatform().trim().isEmpty()||properties.getSourcePlatform().length()>128)throw new FudaException(503,50303,"Application configuration unavailable");
        String appId=header(request,"X-App-Id"),timestamp=header(request,"X-Timestamp"),nonce=header(request,"X-Nonce"),signature=header(request,"X-Signature");
        if(appId==null||!appId.matches("[A-Za-z0-9_-]{1,64}")||timestamp==null||!timestamp.matches("[0-9]{1,12}")
                ||nonce==null||!nonce.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
                ||signature==null||!signature.matches("[0-9a-f]{64}"))throw unauthorized();
        FudaProperties.Application app=properties.getApplications().get(appId);
        if(app==null||!app.isEnabled())throw unauthorized();
        long seconds;try{seconds=Long.parseLong(timestamp);}catch(Exception e){throw unauthorized();}
        if(Math.abs(clock.instant().getEpochSecond()-seconds)>300)throw new FudaException(401,40102,"Request timestamp outside allowed window");
        byte[] key=secret(app);
        String canonical="POST\n"+request.getRequestURI()+"\n"+appId+"\n"+timestamp+"\n"+nonce+"\n"+sha256(body);
        if(!equal(signature,hmac(key,canonical)))throw unauthorized();
        if(!nonces.claim(appId,nonce.toLowerCase(Locale.ROOT)))throw new FudaException(409,40902,"Nonce already used; retry with a new nonce");
        return new Principal(appId,app,key);
    }
    private static String header(HttpServletRequest r,String name){Enumeration<String> values=r.getHeaders(name);if(values==null||!values.hasMoreElements())return null;String v=values.nextElement();if(values.hasMoreElements())throw unauthorized();return v;}
    private static FudaException unauthorized(){return new FudaException(401,40101,"Invalid application authentication");}
    static byte[] secret(FudaProperties.Application app){try{byte[] key=Base64.getDecoder().decode(app.getSecretBase64());if(key.length!=32)throw new IllegalArgumentException();return key;}catch(Exception e){throw new FudaException(503,50303,"Application configuration unavailable");}}
    public static String sha256(byte[] bytes){try{return hex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(Exception e){throw new IllegalStateException(e);}}
    public static String hmac(byte[] key,String text){try{Mac m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(key,"HmacSHA256"));return hex(m.doFinal(text.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    static boolean equal(String a,String b){return MessageDigest.isEqual(a.getBytes(StandardCharsets.US_ASCII),b.getBytes(StandardCharsets.US_ASCII));}
    private static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte v:b)s.append(String.format(Locale.ROOT,"%02x",v&255));return s.toString();}
    public static final class Principal {
        public final String appId;public final FudaProperties.Application application;final byte[] key;
        public Principal(String appId,FudaProperties.Application application,byte[] key){this.appId=appId;this.application=application;this.key=key.clone();}
    }
}
