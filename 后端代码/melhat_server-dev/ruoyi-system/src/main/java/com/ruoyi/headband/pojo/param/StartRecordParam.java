package com.ruoyi.headband.pojo.param;

import lombok.Data;

@Data
public class StartRecordParam {
    /**
     * 频道名称
     */
    private String channelName;
    /**
     * 录制时长（秒）
     */
    private Integer recordTimeLength;

}
