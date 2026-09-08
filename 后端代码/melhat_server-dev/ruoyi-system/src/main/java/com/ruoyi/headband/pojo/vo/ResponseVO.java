package com.ruoyi.headband.pojo.vo;

import com.alibaba.fastjson2.JSONObject;
import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class ResponseVO {

    private int code;

    private String message;

    private Object data;
}
