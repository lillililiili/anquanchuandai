package com.ruoyi.web.controller.business;

import com.alibaba.fastjson2.JSON;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.DateUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.headband.pojo.param.GnssNotifyParam;
import com.ruoyi.headband.pojo.param.HelmatAlarm;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.pojo.po.SosAlarmRecord;
import com.ruoyi.helmet.service.IRealTimeAlarmService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.ruoyi.helmet.service.ISosAlarmRecordService;
import com.ruoyi.helmet.vo.SafetyHatListVO;
import com.ruoyi.system.service.ISysConfigService;
import com.ruoyi.system.service.ISysDictTypeService;
import com.ruoyi.system.service.ISysUserService;
import com.ruoyi.system.websocket.WebSocketSever;
import com.ruoyi.system.websocket.WebsocktMsg;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;


@RestController
@RequestMapping("/ext")
@Api(tags = "对外接口")
@Slf4j
public class ExternalController {

    @Autowired
    private ISysUserService sysUserService;

    @Autowired
    private ISysConfigService sysConfigService;
    @Autowired
    private ISysDictTypeService sysDictTypeService;
    @Autowired
    private ISafetyHatInfoService safetyHatInfoService;
    @Autowired
    private IRealTimeAlarmService realTimeAlarmService;
    @Autowired
    private ISafetyHatLocationRecordService safetyHatLocationRecordService;
    @Autowired
    private ISosAlarmRecordService sosAlarmRecordService;
    @Autowired
    private HeadbandService headbandService;

    @Autowired
    private ExecutorService executorService = Executors.newCachedThreadPool();

    /**
     * 安全帽报警通知
     *
     * @param param
     */
    @PostMapping("/helmetAlarm")
    @ApiOperation(value = "安全帽报警推送")
    public ResponseVO helmetAlarm(@RequestBody HelmatAlarm param) {
        ResponseVO back = null;
        String type = param == null ? null : param.getType();
        String helmetSn = param == null ? null : param.getHelmetSn();
        String startTime = param == null ? null : param.getStartTime();
        String endTime = param == null ? null : param.getEndTime();
        log.info("[/ext/helmetAlarm] request params: type={}, helmetSn={}, startTime={}, endTime={}",
                type, helmetSn, startTime, endTime);
        if (StringUtils.isBlank(helmetSn)) {
            log.error("帽子编号不能是空");
            back = new ResponseVO(200, "帽子编号不能是空", null);
            return back;
        }
        if (StringUtils.isBlank(type)) {
            log.error("告警类型不能是空");
            back = new ResponseVO(200, "告警类型不能是空", null);
            return back;
        }
        SafetyHatListVO hat = safetyHatInfoService.getByHatNumber(helmetSn);
        if (hat == null) {
            log.error("帽子-{}不存在", helmetSn);
            back = new ResponseVO(200, "帽子不存在", null);
            return back;
        }
        RealTimeAlarm alarm = new RealTimeAlarm();
        alarm.setHatNumber(helmetSn);
        alarm.setHatId(hat.getId());
        alarm.setUserId(hat.getBindUserId());
        alarm.setUserName(hat.getBindUserName());
        alarm.setAlarmType(type);
        alarm.setAlarmLevel("2");
        if (startTime != null) {
            alarm.setAlarmStartTime(DateUtils.dateTime(DateUtils.YYYY_MM_DD_HH_MM_SS, startTime));
        }
        if (endTime != null) {
            alarm.setAlarmEndTime(DateUtils.dateTime(DateUtils.YYYY_MM_DD_HH_MM_SS, endTime));
        }
        alarm.setCreateTime(new Date());
        realTimeAlarmService.save(alarm);

        //推送到前端
        WebSocketSever.sendAllMessage(JSON.toJSONString(new WebsocktMsg("alarm", alarm)));

        back = new ResponseVO(200, "success", null);
        return back;
    }

    /**
     * GNSS 位置信息推送
     *
     * @param param GNSS 位置信息参数封装
     */
    @PostMapping("/notifyGnss")
    @ApiOperation(value = "安全帽定位推送")
    public ResponseVO gnss(@RequestBody GnssNotifyParam param) {
        ResponseVO back = null;
        String helmetSn = param == null ? null : param.getHelmetSn();
        String latitude = param == null ? null : param.getLatitude();
        String longitude = param == null ? null : param.getLongitude();
        String speed = param == null ? null : param.getSpeed();
        String altitude = param == null ? null : param.getAltitude();
        String timestamp = param == null ? null : param.getTimestamp();
        log.info("[/ext/notifyGnss] request params: helmetSn={}, latitude={}, longitude={}, speed={}, altitude={}, timestamp={}",
                helmetSn, latitude, longitude, speed, altitude, timestamp);
        if (StringUtils.isBlank(helmetSn)) {
            log.error("帽子编号不能是空");
            back = new ResponseVO(200, "帽子编号不能是空", null);
            return back;
        }
        if (StringUtils.isBlank(latitude)) {
            log.error("定位纬度不能是空");
            back = new ResponseVO(200, "定位纬度不能是空", null);
            return back;
        }
        if (StringUtils.isBlank(longitude)) {
            log.error("定位经度不能是空");
            back = new ResponseVO(200, "定位经度不能是空", null);
            return back;
        }
        if (StringUtils.isBlank(timestamp)) {
            log.error("定位时间不能是空");
            back = new ResponseVO(200, "定位时间不能是空", null);
            return back;
        }
        SafetyHatListVO hat = safetyHatInfoService.getByHatNumber(helmetSn);
        if (hat == null) {
            log.error("帽子-{}不存在", helmetSn);
            back = new ResponseVO(200, "帽子不存在", null);
            return back;
        }
        SafetyHatLocationRecord record = new SafetyHatLocationRecord();
        record.setHatId(hat.getId());
        record.setHatNumber(helmetSn);
        record.setUserId(hat.getBindUserId());
        record.setUserName(hat.getBindUserName());
        record.setLng(longitude);
        record.setLat(latitude);
        record.setSpeed(speed);
        record.setAltitude(altitude);
        record.setTimestamp(timestamp);
        record.setCreateTime(new Date());
        safetyHatLocationRecordService.save(record);

        //推送到前端
//        WebSocketSever.sendAllMessage(JSON.toJSONString(new WebsocktMsg("location",record)));
        back = new ResponseVO(200, "success", null);
        return back;
    }

    /**
     * sos
     *
     * @param param
     */
    @PostMapping("/sosCall")
    @ApiOperation(value = "安全帽SOS呼叫")
    public ResponseVO sosCall(@RequestBody GnssNotifyParam param) {
        ResponseVO back = null;
        String helmetSn = param == null ? null : param.getHelmetSn();
        String latitude = param == null ? null : param.getLatitude();
        String longitude = param == null ? null : param.getLongitude();
        log.info("[/ext/sosCall] request params: helmetSn={}, latitude={}, longitude={}",
                helmetSn, latitude, longitude);
        if (StringUtils.isBlank(helmetSn)) {
            log.error("帽子编号不能是空");
            back = new ResponseVO(200, "帽子编号不能是空", null);
            return back;
        }
        SafetyHatListVO hat = safetyHatInfoService.getByHatNumber(helmetSn);
        if (hat == null) {
            log.error("帽子-{}不存在", helmetSn);
            back = new ResponseVO(200, "帽子不存在", null);
            return back;
        }

        SosAlarmRecord record = new SosAlarmRecord();
        record.setHatId(hat.getId());
        record.setHatNumber(helmetSn);
        record.setUserId(hat.getBindUserId());
        record.setUserName(hat.getBindUserName());
        record.setLng(longitude);
        record.setLat(latitude);
        record.setCallTime(new Date());
        record.setCreateTime(new Date());
        sosAlarmRecordService.save(record);

        back = new ResponseVO(200, "success", null);
        //呼叫帽子
        executorService.execute(() -> callHat(helmetSn));
        return back;

    }

    public void callHat(String helmetSn){
        try {
            List<String> allNumbers = new ArrayList<>();
            allNumbers.add(helmetSn);
            Map<String, Object> callparam = new HashMap<>();
            callparam.put("helmetSnList", allNumbers);
            ResponseVO responseVO = headbandService.agoraToken(callparam);
            //推送到前端
            WebSocketSever.sendAllMessage(JSON.toJSONString(new WebsocktMsg("sos", responseVO)));
        } catch (Exception e) {
            log.error("呼叫安全帽时异常", e);
            throw new ServiceException("呼叫安全帽时异常");
        }
    }


}
