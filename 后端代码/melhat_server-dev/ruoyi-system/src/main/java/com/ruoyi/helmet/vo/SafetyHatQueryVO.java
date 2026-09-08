package com.ruoyi.helmet.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.Date;

@Data
@ApiModel(value = "安全帽查询信息", description = "安全帽查询信息")
public class SafetyHatQueryVO {
    @ApiModelProperty(value = "安全帽sn")
    private String hatNumber;

    @ApiModelProperty(value = "安全帽绑定人员")
    private String bindUserName;

    @ApiModelProperty(value = "安全帽绑定分组")
    private String bindGroup;

    @ApiModelProperty(value = "安全帽状态（1正常使用 0已离线）")
    private String status;

    @ApiModelProperty(value = "安全帽绑定时间查询开始时间")
    private Date startTime;

    @ApiModelProperty(value = "安全帽绑定时间查询结束时间")
    private Date endTime;
}