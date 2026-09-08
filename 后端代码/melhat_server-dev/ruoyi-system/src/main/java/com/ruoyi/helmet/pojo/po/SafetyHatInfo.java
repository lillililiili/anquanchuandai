package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 安全帽信息表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("safety_hat_info")
@EqualsAndHashCode(callSuper = true)
public class SafetyHatInfo extends Model<SafetyHatInfo> {

    private static final long serialVersionUID = 1L;

    /**
     *
     */
    private Long id;
    /**
     * 安全帽编号
     */
    private String hatNumber;
    /**
     * 绑定人员id
     */
    private Long bindUserId;
    /**
     * 绑定人员姓名
     */
    private String bindUserName;
    /**
     * 所属群组id
     */
    private Long bindGroupId;
    /**
     * 所属群组
     */
    private String bindGroup;
    /**
     * 绑定时间
     */
    private Date bindTime;
    /**
     * 状态（1正常使用/ 0离线）
     */
    private String status;
    /**
     * CPU使用率
     */
    private BigDecimal cpuUsage;
    /**
     * 存储空间使用率
     */
    private BigDecimal storageUsage;
    /**
     * 电量剩余百分比
     */
    private BigDecimal electricityUsage;
    /**
     * 告警次数
     */
    private Integer alarmCount;
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

    private String videoUrl;//音视频web地址

    private String rtcPlayConfig;//音视频移动端播放配置串

    private String uid;//通话uid

}
