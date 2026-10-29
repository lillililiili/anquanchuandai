package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;

/** Live device sessions, supplied by the belt gateway without reading GuardianStore. */
public interface DirectBeltAccess {
    JSONObject status(String deviceId);
}
