package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.time.Clock;
import java.util.*;
import static com.ruoyi.fuda.FudaMapping.*;

@RestController
public class FudaController {
    private static final int MAX_BODY=65536;
    private final FudaAuth auth;private final FudaQueryService queries;private final Clock clock;
    private final ObjectMapper json=new ObjectMapper().enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION).enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
    public FudaController(FudaAuth auth,FudaQueryService queries,@Qualifier("fudaClock") Clock clock){this.auth=auth;this.queries=queries;this.clock=clock;}
    @PostMapping(value={"/openapi/wearables/v2/positions/query","/openapi/wearables/v2/statuses/query","/openapi/wearables/v2/alarms/query"},produces="application/json;charset=UTF-8")
    public ResponseEntity<JSONObject> query(HttpServletRequest request){
        String requestId=UUID.randomUUID().toString();
        try{
            String contentType=request.getContentType();
            if(contentType==null||!contentType.toLowerCase(Locale.ROOT).matches("application/json(?:\\s*;\\s*charset=(?:utf-8|\"utf-8\"))?"))throw new FudaException(415,41501,"Content-Type application/json with UTF-8 required");
            if(request.getHeader("Content-Encoding")!=null)throw new FudaException(415,41501,"Content encoding is not supported");
            byte[] body=read(request);FudaAuth.Principal principal=auth.authenticate(request,body);
            JSONObject input=parse(body);String path=request.getRequestURI();String kind=path.contains("/positions/")?"positions":path.contains("/statuses/")?"statuses":"alarms";
            JSONObject data=queries.query(kind,principal,input);
            return respond(200,object("code",0,"message","success","requestId",requestId,"serverTime",now(clock),"data",data));
        }catch(FudaException e){return respond(e.status,object("code",e.code,"message",e.getMessage(),"requestId",requestId,"serverTime",now(clock),"data",null));}
        catch(Exception e){org.slf4j.LoggerFactory.getLogger(getClass()).warn("Fuda query unavailable; requestId={}, errorType={}",requestId,e.getClass().getSimpleName());
            return respond(503,object("code",50300,"message","Service temporarily unavailable","requestId",requestId,"serverTime",now(clock),"data",null));}
    }
    private JSONObject parse(byte[] body){
        try{
            String source=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(body)).toString();
            JsonNode node=json.readTree(source);if(node==null||!node.isObject())throw new IllegalArgumentException();
            return JSONObject.parseObject(node.toString());
        }catch(Exception e){throw FudaException.bad("Invalid UTF-8 JSON object");}
    }
    private byte[] read(HttpServletRequest r)throws IOException {
        if(r.getContentLengthLong()>MAX_BODY)throw new FudaException(413,41301,"Request body exceeds 64 KiB");
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[4096];int n;InputStream input=r.getInputStream();
        while((n=input.read(buffer))!=-1){if(bytes.size()+n>MAX_BODY)throw new FudaException(413,41301,"Request body exceeds 64 KiB");bytes.write(buffer,0,n);}return bytes.toByteArray();
    }
    private ResponseEntity<JSONObject> respond(int status,JSONObject body){return ResponseEntity.status(status).header("Cache-Control","no-store").header("X-Content-Type-Options","nosniff").body(body);}
}
