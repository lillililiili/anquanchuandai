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
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("group_info")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "分组信息", description = "分组信息")
public class GroupInfo extends Model<GroupInfo> {

    private static final long serialVersionUID = 1L;

    /**
     *
     */
    @ApiModelProperty(value = "分组id")
    private Long id;
    /**
     * 分组名称，最长30字
     */
    @ApiModelProperty(value = "分组名称")
    private String groupName;
    /**
     * 分组描述
     */
    @ApiModelProperty(value = "分组描述")
    private String groupDesc;
    /**
     * 安全帽数量
     */
    @ApiModelProperty(value = "安全帽数量")
    private Integer safetyCount;
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
