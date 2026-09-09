package com.ruoyi.wear.helmet.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_ingest_raw")
public class WearIngestRaw
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private String path;
    private String helmetSn;
    private Long deviceId;
    private String messageKey;
    private Date receivedAt;
    private String payloadJson;
    private Integer authOk;
    private String processStatus;
    private String error;
    private Date createTime;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getPath() { return path; }
    public void setPath(String path) { this.path = path; }
    public String getHelmetSn() { return helmetSn; }
    public void setHelmetSn(String helmetSn) { this.helmetSn = helmetSn; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
    public String getMessageKey() { return messageKey; }
    public void setMessageKey(String messageKey) { this.messageKey = messageKey; }
    public Date getReceivedAt() { return receivedAt; }
    public void setReceivedAt(Date receivedAt) { this.receivedAt = receivedAt; }
    public String getPayloadJson() { return payloadJson; }
    public void setPayloadJson(String payloadJson) { this.payloadJson = payloadJson; }
    public Integer getAuthOk() { return authOk; }
    public void setAuthOk(Integer authOk) { this.authOk = authOk; }
    public String getProcessStatus() { return processStatus; }
    public void setProcessStatus(String processStatus) { this.processStatus = processStatus; }
    public String getError() { return error; }
    public void setError(String error) { this.error = error; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
}
