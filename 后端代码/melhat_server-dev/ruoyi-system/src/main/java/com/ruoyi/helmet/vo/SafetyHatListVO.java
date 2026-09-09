package com.ruoyi.helmet.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

@Data
@ApiModel(value = "安全帽信息", description = "安全帽信息")
public class SafetyHatListVO {

    @ApiModelProperty(value = "安全帽id")
    private Long id;

    @ApiModelProperty(value = "所属厂站")
    private Long siteId;

    @ApiModelProperty(value = "安全帽sn")
    private String hatNumber;

    @ApiModelProperty(value = "uid")
    private String uid;//通话uid

    @ApiModelProperty(value = "安全帽绑定分组")
    private String bindGroup;

    @ApiModelProperty(value = "安全帽绑定人员Id")
    private Long bindUserId;

    @ApiModelProperty(value = "安全帽绑定人员")
    private String bindUserName;

    @ApiModelProperty(value = "安全帽绑定时间")
    private Date bindTime;

    @ApiModelProperty(value = "安全帽电量")
    private BigDecimal electricityUsage;

    @ApiModelProperty(value = "安全帽存储空间")
    private BigDecimal storageUsage;

    @ApiModelProperty(value = "安全帽状态（1正常使用 0已离线）")
    private String status;          // 原始状态值

    private String statusText;      // 中文状态文本
    private String electricityColor; // 用于前端进度条颜色
    private String storageColor;

    @ApiModelProperty(value = "告警次数")
    private Integer alarmCount;

    @ApiModelProperty(value = "录音数量")
    private Integer recordCount;    // 录音数量（需关联其他表或统计）

    @ApiModelProperty(value = "拍摄图片数量")
    private Integer photoCount;     // 拍摄图片数量

    @ApiModelProperty(value = "拍摄视频数量")
    private Integer videoCount;     // 拍摄视频数量

    @ApiModelProperty(value = "音视频web地址")
    private String videoUrl;//音视频web地址

    @ApiModelProperty(value = "音视频移动端播放配置串")
    private String rtcPlayConfig;//音视频移动端播放配置串

    @ApiModelProperty(value = "纬度")
    private String latitude;
    @ApiModelProperty(value = "经度")
    private String longitude;


}
