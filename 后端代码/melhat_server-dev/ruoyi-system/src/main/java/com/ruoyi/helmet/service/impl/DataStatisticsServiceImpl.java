package com.ruoyi.helmet.service.impl;

import com.ruoyi.helmet.mapper.FileRecordMapper;
import com.ruoyi.helmet.mapper.IntercomRecordMapper;
import com.ruoyi.helmet.mapper.RealTimeAlarmMapper;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.mapper.TtsTextSynthesisBroadcastMapper;
import com.ruoyi.helmet.service.DataStatisticsService;
import com.ruoyi.helmet.vo.AppDataStat;
import com.ruoyi.helmet.vo.DashboardDataStat;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class DataStatisticsServiceImpl implements DataStatisticsService {

    @Autowired
    private SafetyHatInfoMapper safetyHatInfoMapper;

    @Autowired
    private RealTimeAlarmMapper realTimeAlarmMapper;

    @Autowired
    private FileRecordMapper fileRecordMapper;

    @Autowired
    private IntercomRecordMapper intercomRecordMapper;

    @Autowired
    private TtsTextSynthesisBroadcastMapper ttsTextSynthesisBroadcastMapper;

    @Override
    public AppDataStat getAppDataStat() {
        AppDataStat stat = new AppDataStat();
        
        // 查询帽子总数
        Integer hatCount = safetyHatInfoMapper.selectCount(null);
        stat.setHatCount(hatCount);
        
        // 查询需要处理的告警数（未处理的告警）
        Integer alarmCount = realTimeAlarmMapper.countUnhandledAlarms();
        stat.setAlarmCount(alarmCount);
        
        // 查询图片总数（文件类型为 'image'）
        Integer photoCount = safetyHatInfoMapper.countPhotoByHatId(null);
        stat.setPhotoCount(photoCount);
        
        // 查询对讲记录总数
        Integer recordCount = intercomRecordMapper.countIntercomRecords();
        stat.setRecordCount(recordCount);
        
        // 查询 TTS 广播记录总数
        Integer ttsBroadcastCount = ttsTextSynthesisBroadcastMapper.countTtsBroadcastRecords();
        stat.setTtsBroadcastCount(ttsBroadcastCount);
        
        return stat;
    }
    
    @Override
    public DashboardDataStat getDashboardDataStat() {
        DashboardDataStat stat = new DashboardDataStat();
        
        // 基础统计
        // 在线人员数量
        Integer onlineUsers = safetyHatInfoMapper.countOnlineUsers();
        stat.setOnlineUsers(onlineUsers);
        
        // 今日告警数量
        Integer todayAlarms = realTimeAlarmMapper.countTodayAlarms();
        stat.setTodayAlarms(todayAlarms);
        
        // 设备正常率
        stat.setDeviceNormalRate(safetyHatInfoMapper.countDeviceNormalRate());
        
        // 安全帽总数
        Integer hatCount = safetyHatInfoMapper.selectCount(null);
        stat.setHatCount(hatCount);
        
        // 未处理告警数
        Integer unhandledAlarms = realTimeAlarmMapper.countUnhandledAlarms();
        stat.setUnhandledAlarms(unhandledAlarms);
        
        // 图片总数
        Integer photoCount = safetyHatInfoMapper.countPhotoByHatId(null);
        stat.setPhotoCount(photoCount);
        
        // 对讲记录总数
        Integer intercomCount = intercomRecordMapper.countIntercomRecords();
        stat.setIntercomCount(intercomCount);
        
        // TTS 广播总数
        Integer ttsBroadcastCount = ttsTextSynthesisBroadcastMapper.countTtsBroadcastRecords();
        stat.setTtsBroadcastCount(ttsBroadcastCount);
        
        // 今日统计
        // 今日对讲记录数
        Integer todayIntercomCount = intercomRecordMapper.countTodayIntercomRecords();
        stat.setTodayIntercomCount(todayIntercomCount);
        
        // 今日 TTS 广播数
        Integer todayTtsBroadcastCount = ttsTextSynthesisBroadcastMapper.countTodayTtsBroadcastRecords();
        stat.setTodayTtsBroadcastCount(todayTtsBroadcastCount);
        
        // 类型统计
        // 告警类型统计
        List<Map<String, Object>> alarmTypeStats = realTimeAlarmMapper.countAlarmByType();
        stat.setAlarmTypeStats(alarmTypeStats);
        
        // 对讲类型统计
        List<Map<String, Object>> intercomTypeStats = intercomRecordMapper.countIntercomByType();
        stat.setIntercomTypeStats(intercomTypeStats);
        
        // TTS 广播类型统计
        List<Map<String, Object>> ttsTypeStats = ttsTextSynthesisBroadcastMapper.countTtsByType();
        stat.setTtsTypeStats(ttsTypeStats);
        
        return stat;
    }
}
