package com.ruoyi.helmet.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel(value = "app 数据统计信息", description = "app 数据统计信息")
public class AppDataStat {

    @ApiModelProperty(value = "安全帽数量")
    private  Integer  hatCount;

    @ApiModelProperty(value = "需要处理的告警数")
    private  Integer alarmCount;

    @ApiModelProperty(value = "拍摄图片数量")
    private Integer photoCount;

    @ApiModelProperty(value = "录音数量")
    private Integer recordCount;

    @ApiModelProperty(value = "TTS 广播数量")
    private Integer ttsBroadcastCount;

}
