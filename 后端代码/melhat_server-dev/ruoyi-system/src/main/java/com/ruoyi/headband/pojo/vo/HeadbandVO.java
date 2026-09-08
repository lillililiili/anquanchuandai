package com.ruoyi.headband.pojo.vo;

import lombok.Data;

@Data
public class HeadbandVO {

    //安全帽SN
    private String  helmetSn;
    //通话时的uid号
    private String  uid_device;

    /**
     * 是否在线
     * 1: 在线
     * 0: 离线
     */
    private String  online;

    //音视频web地址
    private String  videoUrl;

    //音视频移动端播放配置串
    private String  rtcPlayConfig;

    //纬度
    private String  latitude;
    //经度
    private String  longitude;
    //速度
    private String  speed;
    //高度
    private String  attitude;
    //时间戳
    private String  timestamp;




}
