package com.ruoyi.headband.pojo.param;

import lombok.AllArgsConstructor;
import lombok.Data;

import java.util.List;

@Data
@AllArgsConstructor
public class GroupCallParam {

    /**
     * 安全帽SN
     */
    private List<String> helmetSnList;

    /**
     * 是否开启录制
     * 缺省： false
     */
    private boolean enableRecodring;
}
