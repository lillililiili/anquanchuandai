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
 * 安全帽定位记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("safety_hat_location_record")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "安全帽定位记录", description = "安全帽定位记录")
public class SafetyHatLocationRecord extends Model<SafetyHatLocationRecord> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键id
     */
    @ApiModelProperty(value = "记录id")
    private Long id;
    /**
     * 帽子id
     */
    @ApiModelProperty(value = "帽子id")
    private Long hatId;
    /**
     * 安全帽编号
     */
    @ApiModelProperty(value = "安全帽编号")
    private String hatNumber;
    /**
     * 用户id
     */
    @ApiModelProperty(value = "安全帽用户id")
    private Long userId;
    /**
     * 用户名称
     */
    @ApiModelProperty(value = "安全帽用户名称")
    private String userName;
    /**
     * 经度
     */
    @ApiModelProperty(value = "经度")
    private String lng;
    /**
     * 纬度
     */
    @ApiModelProperty(value = "纬度")
    private String lat;
    /**
     * 移动速度
     */
    @ApiModelProperty(value = "移动速度")
    private String speed;
    /**
     * 时间戳 xxxx-xx-xx xx:xx:xx
     */
    @ApiModelProperty(value = "时间戳")
    private String timestamp;
    /**
     * 天线海拔高度，单位为米（M），这里海拔高度是 112.4283 米。
     */
    @ApiModelProperty(value = "天线海拔高度")
    private String altitude;
    /**
     * 删除标志（0代表存在 2代表删除）
     */
    @TableLogic
    private Integer delFlag;
    /**
     * 创建时间
     */
    private Date createTime;
    /**
     * 创建者
     */
    private String createBy;
    /**
     * 更新时间
     */
    private Date updateTime;
    /**
     * 更新者
     */
    private String updateBy;

    // 非数据库字段，用于前端展示“设备+人员”信息
    @TableField(exist = false)
    @ApiModelProperty(value = "帽子sn+人员信息")
    private SafetyHatInfo deviceInfo;    // 如：“安全帽 #A001 - 张工”

    // 可选：关联的视频文件URL（如果轨迹点有关联视频）
    @TableField(exist = false)
    @ApiModelProperty(value = "关联的视频文件URL")
    private String relatedVideoUrl;

}
