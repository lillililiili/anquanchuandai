package com.ruoyi.wear.admin.dto;

import java.util.Date;
import com.ruoyi.common.annotation.Excel;

public class GenericLedgerRow
{
    @Excel(name = "记录ID") private String id;
    @Excel(name = "编码/序列号") private String code;
    @Excel(name = "名称/人员") private String name;
    @Excel(name = "类型") private String type;
    @Excel(name = "状态") private String status;
    @Excel(name = "厂站ID") private String siteId;
    @Excel(name = "关联信息") private String relation;
    @Excel(name = "开始时间", width = 22, dateFormat = "yyyy-MM-dd HH:mm:ss") private Date startTime;
    @Excel(name = "结束时间", width = 22, dateFormat = "yyyy-MM-dd HH:mm:ss") private Date endTime;
    @Excel(name = "备注") private String remark;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getRelation() { return relation; }
    public void setRelation(String relation) { this.relation = relation; }
    public Date getStartTime() { return startTime; }
    public void setStartTime(Date startTime) { this.startTime = startTime; }
    public Date getEndTime() { return endTime; }
    public void setEndTime(Date endTime) { this.endTime = endTime; }
    public String getRemark() { return remark; }
    public void setRemark(String remark) { this.remark = remark; }
}
