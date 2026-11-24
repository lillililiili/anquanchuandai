package com.ruoyi.melhat.split;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import java.net.URI;
import java.util.*;

@Component
@ConfigurationProperties(prefix="melhat.split")
public class SplitHelmetProperties {
    private boolean enabled;
    private String baseUrl="https://api.hel.epplink.com:30090";
    private String username="",password="",callbackSecret="",allowedDevices="",fileOrigins="";
    private int timeoutSeconds=15, freshnessSeconds=300, leaseSeconds=180;
    public boolean isEnabled(){return enabled;} public void setEnabled(boolean v){enabled=v;}
    public String getBaseUrl(){return baseUrl;} public void setBaseUrl(String v){baseUrl=v;}
    public String getUsername(){return username;} public void setUsername(String v){username=v;}
    public String getPassword(){return password;} public void setPassword(String v){password=v;}
    public String getClientId(){return username;} public void setClientId(String v){username=v;}
    public String getClientSecret(){return password;} public void setClientSecret(String v){password=v;}
    public String getCallbackSecret(){return callbackSecret;} public void setCallbackSecret(String v){callbackSecret=v;}
    public String getAllowedDevices(){return allowedDevices;} public void setAllowedDevices(String v){allowedDevices=v;}
    public String getFileOrigins(){return fileOrigins;} public void setFileOrigins(String v){fileOrigins=v;}
    public int getTimeoutSeconds(){return timeoutSeconds;} public void setTimeoutSeconds(int v){timeoutSeconds=v;}
    public int getFreshnessSeconds(){return freshnessSeconds;} public void setFreshnessSeconds(int v){freshnessSeconds=v;}
    public int getLeaseSeconds(){return leaseSeconds;} public void setLeaseSeconds(int v){leaseSeconds=v;}
    public Set<String> allowed(){Set<String>s=new LinkedHashSet<>();for(String v:allowedDevices.split(","))if(!v.trim().isEmpty())s.add(v.trim());return s;}
    public void validate(){
        if(!enabled)return;
        URI u=URI.create(baseUrl);
        if(!"https".equals(u.getScheme())||u.getHost()==null||u.getRawUserInfo()!=null||u.getRawQuery()!=null||u.getRawFragment()!=null||!Arrays.asList("","/").contains(u.getPath()))throw new IllegalArgumentException("分体帽厂家地址必须为HTTPS源站");
        if(username.isEmpty()||password.isEmpty()||callbackSecret.length()<32||allowed().isEmpty())throw new IllegalArgumentException("分体帽启用前须配置独立厂家凭据、回调密钥和设备白名单");
        for(String sn:allowed())if(!sn.matches("[A-Za-z0-9._-]{1,64}"))throw new IllegalArgumentException("分体帽白名单设备标识无效");
        for(String origin:fileOrigins.split(","))if(!origin.trim().isEmpty()){URI f=URI.create(origin.trim());if(!Arrays.asList("http","https").contains(f.getScheme())||f.getHost()==null||f.getRawUserInfo()!=null||f.getRawQuery()!=null||f.getRawFragment()!=null||!Arrays.asList("","/").contains(f.getPath()))throw new IllegalArgumentException("分体帽文件白名单必须为完整HTTP或HTTPS源站，不含路径或凭据");}
        if(timeoutSeconds<1||timeoutSeconds>60||freshnessSeconds<30||freshnessSeconds>3600||leaseSeconds<120||leaseSeconds>300)throw new IllegalArgumentException("分体帽超时配置无效");
    }
}
