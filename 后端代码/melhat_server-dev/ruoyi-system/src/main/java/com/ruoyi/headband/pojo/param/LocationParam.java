package com.ruoyi.headband.pojo.param;


import lombok.Data;

@Data
public class LocationParam {

    private String device_flashid; //设备标识

    private String lat;  //经纬度

    private String lng;  //经纬度

    /**
     * 定位质量指示，取值含义如下：
     * 0：定位无效
     * 1：GPS 单点定位
     * 2：差分 GPS 定位
     * 3：PPS 定位
     * 4：实时动态定位（RTK）固定解
     * 5：实时动态定位（RTK）浮点解
     * 6：估算（航位推算）定位
     * 7：手工输入模式
     * 8：模拟模式
     */
    private Integer fix_quality; //定位质量指示
    /**
     * 水平定位精度DOP值的含义
     * DOP Value Rating Description
     * 1 理想情况 最高置信等级，适用于那些全天候需要最高精度的应用。
     * 1-2 优秀 这个置信等级，能够满足除了1中的绝大多数应用
     * 2-5 良好 可以用于路线导航
     * 5-10 中等 可以用于计算。更广阔的天空能够提高置信水平。
     * 10-20 及格 低等级置信水平，应该丢弃，或者仅仅对当前位置非常初略的估计。
     * 20 不及格 这个等级的置信水平，测量已经非常不精确了。当定位精度为6m，dop = 50的时候，误差已经有300m 之巨 (50 DOP × 6 meters)。
     */
    private String hdop; //水平定位精度DOP值的含义

    private String altitude; //天线海拔高度，单位为米（M），这里海拔高度是 112.4283 米。

    private String geoidal_separation; //大地水准面高度，单位为米（M），表示大地水准面与 WGS84 椭球面的高度差。
}
