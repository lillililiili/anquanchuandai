package com.ruoyi.helmet.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * Dashboard 数据统计信息
 */
@Data
@ApiModel(value = "Dashboard 数据统计信息", description = "Dashboard 数据统计信息")
public class DashboardDataStat {

    @ApiModelProperty(value = "在线人员数量")
    private Integer onlineUsers;

    @ApiModelProperty(value = "今日告警数量")
    private Integer todayAlarms;

    @ApiModelProperty(value = "设备正常率")
    private BigDecimal deviceNormalRate;

    @ApiModelProperty(value = "安全帽总数")
    private Integer hatCount;

    @ApiModelProperty(value = "未处理告警数")
    private Integer unhandledAlarms;

    @ApiModelProperty(value = "图片总数")
    private Integer photoCount;

    @ApiModelProperty(value = "对讲记录总数")
    private Integer intercomCount;

    @ApiModelProperty(value = "TTS 广播总数")
    private Integer ttsBroadcastCount;

    @ApiModelProperty(value = "今日对讲记录数")
    private Integer todayIntercomCount;

    @ApiModelProperty(value = "今日 TTS 广播数")
    private Integer todayTtsBroadcastCount;

    @ApiModelProperty(value = "告警类型统计列表")
    private List<Map<String, Object>> alarmTypeStats;

    @ApiModelProperty(value = "对讲类型统计列表")
    private List<Map<String, Object>> intercomTypeStats;

    @ApiModelProperty(value = "TTS 广播类型统计列表")
    private List<Map<String, Object>> ttsTypeStats;

}
