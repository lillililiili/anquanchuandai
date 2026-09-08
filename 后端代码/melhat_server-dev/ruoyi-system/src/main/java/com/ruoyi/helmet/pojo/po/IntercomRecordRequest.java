package com.ruoyi.helmet.pojo.po;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class IntercomRecordRequest {

    @ApiModelProperty(value = "单呼/群呼传：帽子编号:多个,分割")
    private String hatNumber;

    @ApiModelProperty(value = "参与人员：单呼/群呼为为安全帽绑定人员的名字、多个时,分割; 组呼时不用传")
    private String participant;


    @ApiModelProperty(value = "组呼用:组id")
    private String groupId;

    /**
     * 是否开启录制
     * 缺省： false
     */
    @ApiModelProperty(value = "是否开启录制: true，否false")
    private boolean enableRecodring;

    @ApiModelProperty(value = "发起呼叫的客户端唯一编号")
    private String clientId;

}
