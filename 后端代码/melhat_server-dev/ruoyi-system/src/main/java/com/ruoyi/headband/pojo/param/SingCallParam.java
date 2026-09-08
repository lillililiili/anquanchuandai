package com.ruoyi.headband.pojo.param;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class SingCallParam {

    /**
     * 安全帽SN
     */
    private String helmetSn;

    /**
     * 是否开启录制
     * 缺省： false
     */
    private boolean enableRecodring;
}
