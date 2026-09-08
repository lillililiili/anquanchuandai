package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** 本地演示兼容接口的原始 JSON 记录。 */
@Data
@TableName("demo_compat_record")
public class DemoCompatRecord {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String moduleKey;
    private String businessKey;
    private String payload;
    private Date createTime;
    private Date updateTime;
}
