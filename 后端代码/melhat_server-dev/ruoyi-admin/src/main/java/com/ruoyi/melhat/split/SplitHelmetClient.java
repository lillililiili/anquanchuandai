package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.*;
import okhttp3.*;
import okio.BufferedSink;
import org.springframework.stereotype.Component;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.TimeUnit;
import static com.ruoyi.melhat.split.SplitTelemetry.*;

/** Dedicated v1.12 transport. Controls are one attempt, including HTTP auth failures. */
@Component
public class SplitHelmetClient {
    private final SplitHelmetProperties properties;
    private final OkHttpClient http;
    private String token;
    private long tokenExpires;
    @org.springframework.beans.factory.annotation.Autowired
    public SplitHelmetClient(SplitHelmetProperties p){this(p,new OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
        .addNetworkInterceptor(chain->{Response r=chain.proceed(chain.request());return r.code()==503?r.newBuilder().removeHeader("Retry-After").build():r;}).build());}
    SplitHelmetClient(SplitHelmetProperties p,OkHttpClient client){properties=p;http=client;p.validate();}
    private OkHttpClient bounded(){return http.newBuilder().connectTimeout(properties.getTimeoutSeconds(),TimeUnit.SECONDS).readTimeout(properties.getTimeoutSeconds(),TimeUnit.SECONDS).writeTimeout(properties.getTimeoutSeconds(),TimeUnit.SECONDS).callTimeout(properties.getTimeoutSeconds(),TimeUnit.SECONDS).build();}
    public boolean configured(){return properties.isEnabled()&&!properties.getClientId().isEmpty()&&!properties.getClientSecret().isEmpty();}
    private HttpUrl endpoint(String path){if(!configured())throw fail(503,"SPLIT_DISABLED","分体帽接入未配置");return HttpUrl.get(properties.getBaseUrl()).newBuilder().encodedPath(path).build();}
    private synchronized String bearer(){
        if(token!=null&&System.currentTimeMillis()<tokenExpires)return token;
        HttpUrl url=endpoint("/api/auth/token").newBuilder().addQueryParameter("client_id",properties.getClientId()).addQueryParameter("client_secret",properties.getClientSecret()).build();
        JSONObject response=request(new Request.Builder().url(url).get().build(),false);JSONObject data=response.getJSONObject("data");
        if(data==null||data.getString("accessToken")==null||data.getString("accessToken").isEmpty()||data.getIntValue("expireTime")<=0||data.getString("tokenType")!=null&&!"Bearer".equals(data.getString("tokenType")))throw fail(502,"SPLIT_AUTH_INVALID","分体帽厂家认证响应无效");
        token="Bearer "+data.getString("accessToken");tokenExpires=System.currentTimeMillis()+Math.max(1,Math.min(86400,data.getIntValue("expireTime"))-30)*1000L;return token;
    }
    public JSONObject get(String path,Map<String,String> query){HttpUrl.Builder url=endpoint(path).newBuilder();if(query!=null)query.forEach(url::addQueryParameter);return request(new Request.Builder().url(url.build()).header("Authorization",bearer()).get().build(),true);}
    public JSONObject post(String path,JSONObject input){return request(new Request.Builder().url(endpoint(path)).header("Authorization",bearer()).post(oneShot(input.toJSONString().getBytes(StandardCharsets.UTF_8),"application/json; charset=utf-8")).build(),true);}
    protected JSONObject request(Request request,boolean authenticated){
        try(Response response=bounded().newCall(request).execute()){
            if(response.code()==401&&authenticated){synchronized(this){token=null;tokenExpires=0;}throw fail(502,"SPLIT_VENDOR_AUTH_EXPIRED","厂家认证已失效，本次请求未自动重发");}
            if(!response.isSuccessful())throw fail(502,"SPLIT_VENDOR_HTTP","分体帽厂家接口未确认请求结果");
            JSONObject json=JSONObject.parseObject(new String(read(response.body(),2*1024*1024),StandardCharsets.UTF_8));
            if(json==null||json.getIntValue("code")!=200)throw fail(502,"SPLIT_VENDOR_REJECTED","分体帽厂家接口未受理或返回无效结果");return json;
        }catch(com.ruoyi.guardian.AdminQueryService.QueryFailed e){throw e;}catch(Exception e){throw fail(502,"SPLIT_VENDOR_UNCONFIRMED","厂家请求结果未确认，请勿重复下发控制");}
    }
    public JSONArray online(List<String> sns){Map<String,String> q=new HashMap<>();q.put("helmetSnList",JSON.toJSONString(sns));q.put("statusOnline","all");q.put("pageNum","1");q.put("pageSize","100");Object data=get("/api/monitor/online",q).get("data");if(!(data instanceof JSONArray))throw fail(502,"SPLIT_VENDOR_INVALID","厂家在线列表格式无效");return (JSONArray)data;}
    public JSONObject files(String sn,int page){Map<String,String> q=new HashMap<>();q.put("pageNum",String.valueOf(page));q.put("pageSize","100");JSONObject data=get("/api/monitor/file/"+sn,q).getJSONObject("data");if(data==null||!(data.get("file_list") instanceof JSONArray))throw fail(502,"SPLIT_VENDOR_INVALID","厂家文件目录格式无效");return data;}
    public String signal(String url,String sn,String kind,String offer){
        validateSignal(url,sn,kind);
        if(offer==null||offer.getBytes(StandardCharsets.UTF_8).length>131072||!offer.startsWith("v=0"))throw fail(400,"INVALID_SDP","会话信令格式无效");
        try(Response response=bounded().newCall(new Request.Builder().url(url).post(oneShot(offer.getBytes(StandardCharsets.UTF_8),"application/sdp")).build()).execute()){
            if(!response.isSuccessful())throw new IOException();String answer=new String(read(response.body(),262144),StandardCharsets.UTF_8);
            if(answer.trim().startsWith("{")){JSONObject json=JSONObject.parseObject(answer);if(json.getIntValue("code")!=0)throw new IOException();answer=json.getString("sdp");}
            if(answer==null||!answer.startsWith("v=0"))throw new IOException();return answer;
        }catch(Exception e){throw fail(502,"SPLIT_SIGNAL_FAILED","安全帽媒体信令未建立，请结束本次会话后重试");}
    }
    public void validateSignal(String value,String sn,String kind){
        try{URI uri=URI.create(value),base=URI.create(properties.getBaseUrl());
            if(!sameOrigin(uri,base)||uri.getRawUserInfo()!=null||uri.getRawFragment()!=null||!"/index/api/webrtc".equals(uri.getPath()))throw new IllegalArgumentException();
            Map<String,String> q=query(uri.getRawQuery());String stream="stream_"+sn+("talk".equals(kind)?"_talk":"");
            if(q.size()!=3||!"app_rl".equals(q.get("app"))||!stream.equals(q.get("stream"))||!("talk".equals(kind)?"push":"play").equals(q.get("type")))throw new IllegalArgumentException();
        }catch(Exception invalid){throw fail(502,"SPLIT_UNSAFE_SIGNAL","厂家返回了不匹配的设备信令地址");}
    }
    public String safeFileUrl(String value,String sn){
        try{URI uri=URI.create(value);if(!Arrays.asList("https","http").contains(uri.getScheme())||uri.getHost()==null||uri.getRawUserInfo()!=null||uri.getRawFragment()!=null||uri.getRawPath().contains("%")||uri.getPath().contains("..")||uri.getPath().contains("\\"))return null;
            boolean allowed=sameOrigin(uri,URI.create(properties.getBaseUrl()));for(String origin:properties.getFileOrigins().split(","))if(!origin.trim().isEmpty()&&sameOrigin(uri,URI.create(origin.trim())))allowed=true;
            if(!allowed||!uri.getPath().contains("/"+sn+"/"))return null;return uri.toASCIIString();
        }catch(RuntimeException bad){return null;}
    }
    /** No vendor authorization is forwarded to the recording-file host. Redirects stay disabled. */
    public Response file(String url,String sn,String range)throws IOException{
        if(safeFileUrl(url,sn)==null)throw fail(502,"SPLIT_UNSAFE_FILE","设备文件地址尚未配置为可信来源");
        Request.Builder b=new Request.Builder().url(url).get();if(range!=null){if(!range.matches("bytes=[0-9]+-[0-9]*"))throw fail(400,"INVALID_RANGE","媒体范围无效");b.header("Range",range);}return bounded().newBuilder().callTimeout(0,TimeUnit.SECONDS).build().newCall(b.build()).execute();
    }
    private static boolean sameOrigin(URI a,URI b){return Objects.equals(a.getScheme(),b.getScheme())&&a.getHost()!=null&&a.getHost().equalsIgnoreCase(b.getHost())&&port(a)==port(b);}
    private static int port(URI u){return u.getPort()<0?("https".equals(u.getScheme())?443:80):u.getPort();}
    private static Map<String,String> query(String raw)throws Exception{Map<String,String> out=new HashMap<>();if(raw==null)return out;for(String pair:raw.split("&")){String[]v=pair.split("=",2);if(v.length!=2||out.put(URLDecoder.decode(v[0],"UTF-8"),URLDecoder.decode(v[1],"UTF-8"))!=null)throw new IllegalArgumentException();}return out;}
    private static RequestBody oneShot(final byte[]bytes,final String content){return new RequestBody(){public MediaType contentType(){return MediaType.get(content);}public long contentLength(){return bytes.length;}public boolean isOneShot(){return true;}public void writeTo(BufferedSink s)throws IOException{s.write(bytes);}};}
    private static byte[] read(ResponseBody body,int max)throws IOException{if(body==null||body.contentLength()>max)throw new IOException();try(InputStream in=body.byteStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[]b=new byte[8192];for(int n;(n=in.read(b))!=-1;){if(out.size()+n>max)throw new IOException();out.write(b,0,n);}return out.toByteArray();}}
}
