package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.Date;

@Data
@TableName("electronic_fence_alarm")
@ApiModel(value = "电子围栏报警信息", description = "电子围栏报警信息")
public class ElectronicFenceAlarm {

    @TableId(type = IdType.AUTO)
    @ApiModelProperty(value = "报警id")
    private Long id;

    @ApiModelProperty(value = "报警用户id")
    private Long userId;            // 用户id
    @ApiModelProperty(value = "报警用户名称")
    private String userName;        // 用户名称（记录）
    @ApiModelProperty(value = "报警帽子编号")
    private String hatNumber;       // 帽子编号(记录)
    @ApiModelProperty(value = "报警帽子id")
    private Long hatId;             // 帽子id
    @ApiModelProperty(value = "触发报警的电子围栏id")
    private Long fenceId;           // 电子围栏id
    @ApiModelProperty(value = "报警类型 (1禁入/非法闯入 2禁出 [同电子围栏类型])")
    private String alarmType;       // 告警类型 (intrusion:非法闯入 timeout:超时停留)
    @ApiModelProperty(value = "报警开始时间")
    private Date alarmStartTime; // 告警开始时间
    @ApiModelProperty(value = "报警结束时间")
    private Date alarmEndTime;   // 告警结束时间
    @ApiModelProperty(value = "报警处理详情")
    private String description;     // 处理详情
    @ApiModelProperty(value = "报警是否已处理 (0否/1是)")
    private Integer isHandled;      // 是否已处理 (0否/1是)
    @ApiModelProperty(value = "报警处理时间")
    private Date handleTime; // 处理时间
    private String delFlag;         // 删除标志 (0代表存在 2代表删除)
    private String createBy;        // 创建者
    private Date createTime; // 创建时间
    private String updateBy;        // 更新者
    private Date updateTime; // 更新时间

    // 非数据库字段：关联围栏名称（用于前端显示）
    @TableField(exist = false)
    @ApiModelProperty(value = "关联围栏名称")
    private String fenceName;

    // 非数据库字段：组合显示“人员(帽子)”
    @TableField(exist = false)
    @ApiModelProperty(value = "人员(帽子sn)")
    private String triggerPersonInfo; // 如：“李工 (安全帽 #002)”
}
