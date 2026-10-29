package com.ruoyi.helmet.service;

import com.alibaba.fastjson2.JSONObject;

/** Credential-free presence of explicitly registered, directly connected helmets. */
public interface DirectHelmetAccess {
    boolean isEnabled();
    boolean supports(String deviceId);
    boolean isOnline(String deviceId);
    JSONObject status(String deviceId);
}
