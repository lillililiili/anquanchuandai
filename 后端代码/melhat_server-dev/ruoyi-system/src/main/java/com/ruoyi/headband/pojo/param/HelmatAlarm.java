package com.ruoyi.headband.pojo.param;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * 头戴报警上报参数封装
 */
@Data
public class HelmatAlarm {

    /**
     * type：告警类型（silent：静默报警，removal：脱帽报警，fall：跌落报警，proximity：近电感应报警）
     */
    @ApiModelProperty(value = "告警类型（silent：静默报警，removal：脱帽报警，fall：跌落报警，proximity：近电感应报警）")
    private String type;

    @ApiModelProperty(value = "来源系统提供的告警名称（可选）")
    private String alarmName;

    @ApiModelProperty(value = "来源系统提供的告警描述（可选）")
    private String alarmDescription;

    /**
     * helmetSn：帽子编号
     */
    @ApiModelProperty(value = "帽子编号")
    private String helmetSn;

    /**
     * startTime：开始时间（yyyy-MM-dd HH:mm:ss）
     */
    @ApiModelProperty(value = "开始时间（yyyy-MM-dd HH:mm:ss）")
    private String startTime;

    /**
     * endTime：结束时间（yyyy-MM-dd HH:mm:ss）
     */
    private String endTime;
}

