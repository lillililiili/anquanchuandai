package com.ruoyi.headband.pojo.param;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * GNSS 位置信息推送参数封装
 */
@Data
public class GnssNotifyParam {

    /**
     * helmetSn：安全帽SN（必填）
     */
    @ApiModelProperty(value = "安全帽SN", required = true)
    private String helmetSn;

    /**
     * latitude：纬度（WGS84）（必填）
     */
    @ApiModelProperty(value = "纬度", required = true)
    private String latitude;

    /**
     * longitude：经度（必填）
     */
    @ApiModelProperty(value = "经度", required = true)
    private String longitude;

    /**
     * speed：移动速度（可选）
     */
    @ApiModelProperty(value = "移动速度")
    private String speed;

    /**
     * altitude：海拔（可选）
     */
    @ApiModelProperty(value = "海拔")
    private String altitude;

    /**
     * timestamp：时间戳（必填，格式：yyyy-MM-dd HH:mm:ss）
     */
    @ApiModelProperty(value = "时间戳,格式：yyyy-MM-dd HH:mm:ss", required = true)
    private String timestamp;
}

