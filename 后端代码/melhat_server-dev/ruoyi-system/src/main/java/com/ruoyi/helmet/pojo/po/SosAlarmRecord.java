package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.util.Date;

/**
 * SOS报警记录表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("sos_alarm_record")
@EqualsAndHashCode(callSuper = true)
public class SosAlarmRecord extends Model<SosAlarmRecord> {

  private static final long serialVersionUID = 1L;
  
    /**
   * 主键ID
   */
      private Long id;
      /**
   * 用户id
   */
      private Long userId;
      /**
   * 用户名称（记录）
   */
      private String userName;
      /**
   * 帽子id
   */
      private Long hatId;
      /**
   * 帽子编号(记录）
   */
      private String hatNumber;
      /**
   * 经度
   */
      private String lng;
      /**
   * 纬度
   */
      private String lat;
      /**
   * 呼叫时间
   */
      private Date callTime;
      /**
   * 处理详情
   */
      private String description;
      /**
   * 处理状态：0-未处理/1-已处理
   */
      private Boolean processStatus;
      /**
   * 处理人
   */
      private String handler;
      /**
   * 处理时间
   */
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
