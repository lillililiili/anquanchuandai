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
 * 对讲记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("intercom_record")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "对讲记录", description = "对讲记录")
public class IntercomRecord extends Model<IntercomRecord> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键ID
     */
    @ApiModelProperty(value = "记录id")
    private Long id;
    /**
     * 对讲类型：01单呼/02群呼/03组呼
     */
    @ApiModelProperty(value = "对讲类型：01单呼/02群呼/03组呼")
    private String intercomType;
    /**
     * 帽子编号:多个,分割
     */
    @ApiModelProperty(value = "帽子编号:多个,分割")
    private String hatNumber;
    /**
     * 参与人员，单呼为个人姓名，群呼/组呼为人员列表或组名
     */
    @ApiModelProperty(value = "参与人员，单呼为安全帽编号，群呼为为安全帽编号拼接,分割/组呼为组id")
    private String participant;
    /**
     * 接收人数（群组/全体人员场景）
     */
    @ApiModelProperty(value = "接收人数（群组/全体人员场景）")
    private Integer recipientCount;
    /**
     * 对讲开始时间
     */
    @ApiModelProperty(value = "对讲开始时间")
    private Date startTime;
    /**
     * 对讲结束时间
     */
    @ApiModelProperty(value = "对讲结束时间")
    private Date endTime;
    /**
     * 对讲时长
     */
    @ApiModelProperty(value = "对讲时长")
    private String duration;
    /**
     * 对讲录音存储路径
     */
    @ApiModelProperty(value = "对讲录音存储路径")
    private String recordPath;
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
