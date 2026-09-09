package com.ruoyi.wear.call.dto;

import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class CallCredentialsDto
{
    private String agoraAppId;
    private String channelName;
    private String agoraUid;
    private String agoraToken;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date expiresAt;
    private Boolean demo;
    private Boolean video;

    public String getAgoraAppId() { return agoraAppId; }
    public void setAgoraAppId(String agoraAppId) { this.agoraAppId = agoraAppId; }
    public String getChannelName() { return channelName; }
    public void setChannelName(String channelName) { this.channelName = channelName; }
    public String getAgoraUid() { return agoraUid; }
    public void setAgoraUid(String agoraUid) { this.agoraUid = agoraUid; }
    public String getAgoraToken() { return agoraToken; }
    public void setAgoraToken(String agoraToken) { this.agoraToken = agoraToken; }
    public Date getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Date expiresAt) { this.expiresAt = expiresAt; }
    public Boolean getDemo() { return demo; }
    public void setDemo(Boolean demo) { this.demo = demo; }
    public Boolean getVideo() { return video; }
    public void setVideo(Boolean video) { this.video = video; }
}
