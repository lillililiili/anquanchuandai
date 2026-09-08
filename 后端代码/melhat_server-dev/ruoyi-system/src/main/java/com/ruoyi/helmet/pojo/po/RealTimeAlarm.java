package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.util.Date;

/**
 * 实时告警表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("real_time_alarm")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "实时告警", description = "实时告警")
public class RealTimeAlarm extends Model<RealTimeAlarm> {

    private static final long serialVersionUID = 1L;

    /**
     * id
     */
    @ApiModelProperty(value = "告警记录id")
    private Long id;
    /**
     * 用户id
     */
    @ApiModelProperty(value = "告警记录用户id")
    private Long userId;
    /**
     * 用户名称（记录）
     */
    @ApiModelProperty(value = "告警记录用户名称")
    private String userName;
    /**
     * 帽子编号(记录）
     */
    @ApiModelProperty(value = "告警记录帽子编号")
    private String hatNumber;
    /**
     * 帽子id
     */
    @ApiModelProperty(value = "告警记录帽子id")
    private Long hatId;
    /**
     * 告警类型（sos:sos报警 silent:静默报警 removal：脱帽报警 fall:跌落报警 proximity：近电感应
     */
    @ApiModelProperty(value = " 告警类型（sos:sos报警 silent:静默报警 removal：脱帽报警 fall:跌落报警 proximity：近电感应")
    private String alarmType;
    /**
     * 告警等级（高/中/低）
     */
    private String alarmLevel;
    /**
     * 告警开始时间
     */
    @ApiModelProperty(value = "告警开始时间")
    private Date alarmStartTime;
    /**
     * 告警结束时间
     */
    @ApiModelProperty(value = "告警结束时间")
    private Date alarmEndTime;
    /**
     * 处理详情
     */
    @ApiModelProperty(value = "处理详情")
    private String description;
    /**
     * 是否已处理（0否/1是）
     */
    @ApiModelProperty(value = "是否已处理（0否/1是）")
    private Integer isHandled;
    /**
     * 处理时间
     */
    @ApiModelProperty(value = "处理时间")
    private Date handleTime;
    /**
     * 删除标志（0代表存在 2代表删除）
     */
    @TableLogic
    private String delFlag;
    /**
     * 创建者
     */
    private String createBy;
    /**
     * 创建时间
     */
    private Date createTime;
    /**
     * 更新者
     */
    private String updateBy;
    /**
     * 更新时间
     */
    private Date updateTime;

}
