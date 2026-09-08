package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 文件记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("file_record")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "文件记录信息", description = "文件记录信息")
public class FileRecord extends Model<FileRecord> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键ID
     */
    @ApiModelProperty(value = "文件记录id")
    private Long id;
    /**
     * 文件名称
     */
    @ApiModelProperty(value = "文件名称")
    private String fileName;
    /**
     * 文件类型：video:视频/audio:音频/ pic:图片
     */
    @ApiModelProperty(value = "文件类型：video:视频/audio:音频/ image:图片")
    private String fileType;
    /**
     * 文件资源地址
     */
    @ApiModelProperty(value = "文件资源地址")
    private String fileUrl;
    /**
     * 帽子ID
     */
    @ApiModelProperty(value = "帽子ID")
    private Long hatId;
    /**
     * 帽子编号
     */
    @ApiModelProperty(value = "帽子编号")
    private String hatNumber;
    /**
     * 用户名
     */
    @ApiModelProperty(value = "用户名")
    private String userName;
    /**
     * 文件大小
     */
    @ApiModelProperty(value = "文件大小")
    private BigDecimal fileSize;
    /**
     * 上传时间
     */
    @ApiModelProperty(value = "上传时间")
    private Date uploadTime;
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

    // 非数据库字段，用于前端展示“设备+人员”信息
    @TableField(exist = false)
    @ApiModelProperty(value = "安全帽sn+人员信息")
    private String deviceInfo;     // 如：“安全帽 #001 - 张工”

}
