package com.ruoyi.web.controller.business;

import com.ruoyi.headband.pojo.param.GnssNotifyParam;
import com.ruoyi.headband.pojo.param.HelmatAlarm;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.wear.helmet.HelmetAdapter;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/ext")
@Api(tags = "对外接口")
@Slf4j
public class ExternalController {

    @Autowired
    private HelmetAdapter helmetAdapter;

    @PostMapping("/helmetAlarm")
    @ApiOperation(value = "安全帽报警推送")
    public ResponseVO helmetAlarm(@RequestBody HelmatAlarm param) {
        log.info("[/ext/helmetAlarm] type={}, helmetSn={}", param == null ? null : param.getType(),
                param == null ? null : param.getHelmetSn());
        return helmetAdapter.handleAlarm(param);
    }

    @PostMapping("/notifyGnss")
    @ApiOperation(value = "安全帽定位推送")
    public ResponseVO gnss(@RequestBody GnssNotifyParam param) {
        log.info("[/ext/notifyGnss] helmetSn={}", param == null ? null : param.getHelmetSn());
        return helmetAdapter.handleGnss(param);
    }

    @PostMapping("/sosCall")
    @ApiOperation(value = "安全帽SOS呼叫")
    public ResponseVO sosCall(@RequestBody GnssNotifyParam param) {
        log.info("[/ext/sosCall] helmetSn={}", param == null ? null : param.getHelmetSn());
        return helmetAdapter.handleSos(param);
    }
}
