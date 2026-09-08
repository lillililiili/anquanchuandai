package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.util.Date;

/**
 * 电子围栏记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("electronic_fence")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "电子围栏信息", description = "电子围栏信息")
public class ElectronicFence extends Model<ElectronicFence> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键ID
     */
    @ApiModelProperty(value = "电子围栏id")
    private Long id;
    /**
     * 围栏名称
     */
    @ApiModelProperty(value = "电子围栏名称")
    private String fenceName;
    /**
     * 围栏类型：见数据字典 elec_fence_type
     */
    @ApiModelProperty(value = "围栏类型：见数据字典 elec_fence_type")
    private String fenceType;
    /**
     * 围栏形状：0多边形围栏（默认为'0') 1圆形围栏 2矩形围栏
     */
    @ApiModelProperty(value = "围栏形状：0多边形围栏（默认为'0') 1圆形围栏 2矩形围栏")
    private String fenceShape;
    /**
     * 报警记录次数
     */
    @ApiModelProperty(value = "报警记录次数")
    private Integer alertCount;
    /**
     * 状态：0-已禁用/1-已启用
     */
    @ApiModelProperty(value = " 状态：0-已禁用/1-已启用")
    private Integer status;
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
    // 非数据库字段：关联的坐标点列表（用于编辑/查看）
    @TableField(exist = false)
    @ApiModelProperty(value = "关联的坐标点列表")
    private java.util.List<ElectronicFenceLatitude> coordinates;

    // 非数据库字段：最近一次报警时间或统计信息（可选）
    @TableField(exist = false)
    @ApiModelProperty(value = "最近一次报警时间")
    private Date lastAlarmTime;
}
