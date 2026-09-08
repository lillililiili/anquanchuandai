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
 * TTS文字语音合成广播记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("tts_text_synthesis_broadcast")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "TTS文字语音合成广播记录", description = "TTS文字语音合成广播记录")
public class TtsTextSynthesisBroadcast extends Model<TtsTextSynthesisBroadcast> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键ID
     */
    @ApiModelProperty(value = "记录id")
    private Long id;
    /**
     * 对讲类型：01单播/02群播/03组播
     */
    @ApiModelProperty(value = "对讲类型：01单播/02群播/03组播")
    private String broadcastType;
    /**
     * 帽子编号:多个,分割
     */
    @ApiModelProperty(value = "帽子编号:多个,分割")
    private String hatNumber;
    /**
     * 接收对象：个人/群/组
     */
    @ApiModelProperty(value = "接收对象：用户名称，多个,分割")
    private String recipient;
    /**
     * 接收人数（群组/全体人员场景）
     */
    @ApiModelProperty(value = "接收人数（群组/全体人员场景）")
    private Integer recipientCount;
    /**
     * 发送时间
     */
    @ApiModelProperty(value = "发送时间")
    private Date sendTime;
    /**
     * 发送内容
     */
    @ApiModelProperty(value = "发送内容")
    private String content;
    /**
     * 操作人
     */
    private String operator;
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
