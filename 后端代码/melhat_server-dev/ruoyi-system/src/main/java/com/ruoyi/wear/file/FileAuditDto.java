package com.ruoyi.wear.file;

import java.math.BigDecimal;
import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class FileAuditDto
{
    private String id;
    private String fileName;
    private String fileType;
    private String hatNumber;
    private String userName;
    private BigDecimal fileSize;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date uploadTime;
    private String deviceInfo;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getFileName() { return fileName; }
    public void setFileName(String fileName) { this.fileName = fileName; }
    public String getFileType() { return fileType; }
    public void setFileType(String fileType) { this.fileType = fileType; }
    public String getHatNumber() { return hatNumber; }
    public void setHatNumber(String hatNumber) { this.hatNumber = hatNumber; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public BigDecimal getFileSize() { return fileSize; }
    public void setFileSize(BigDecimal fileSize) { this.fileSize = fileSize; }
    public Date getUploadTime() { return uploadTime; }
    public void setUploadTime(Date uploadTime) { this.uploadTime = uploadTime; }
    public String getDeviceInfo() { return deviceInfo; }
    public void setDeviceInfo(String deviceInfo) { this.deviceInfo = deviceInfo; }
}
