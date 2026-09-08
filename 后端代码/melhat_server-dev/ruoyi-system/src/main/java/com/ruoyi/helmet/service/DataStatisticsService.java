package com.ruoyi.helmet.service;

import com.ruoyi.helmet.vo.AppDataStat;
import com.ruoyi.helmet.vo.DashboardDataStat;

public interface DataStatisticsService {

    /**
     * 获取 APP 数据统计信息
     * 
     * @return AppDataStat
     */
    AppDataStat getAppDataStat();
    
    /**
     * 获取 Dashboard 数据统计信息
     * 
     * @return DashboardDataStat
     */
    DashboardDataStat getDashboardDataStat();
}