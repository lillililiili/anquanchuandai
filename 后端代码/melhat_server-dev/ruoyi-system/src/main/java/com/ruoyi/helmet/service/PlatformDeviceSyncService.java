package com.ruoyi.helmet.service;

import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 导入平台设备身份及状态，不推测人员绑定、不制造定位或音视频地址。 */
@Service
public class PlatformDeviceSyncService {
    private final HeadbandService platform;
    private final SafetyHatInfoMapper mapper;

    public PlatformDeviceSyncService(HeadbandService platform, SafetyHatInfoMapper mapper) {
        this.platform = platform;
        this.mapper = mapper;
    }

    public List<HeadbandVO> preview() throws Exception {
        Map<String, Object> params = new HashMap<>();
        params.put("helmetSnList", Collections.emptyList());
        params.put("statusOnline", "");
        List<HeadbandVO> devices = platform.getHeadBandList(params);
        if (devices == null) throw new ServiceException("平台设备列表为空响应，未执行同步");
        Set<String> seen = new HashSet<>();
        for (HeadbandVO device : devices) {
            if (device == null || device.getHelmetSn() == null || device.getHelmetSn().trim().isEmpty()
                    || !seen.add(device.getHelmetSn())) {
                throw new ServiceException("平台设备编号缺失或重复，未执行同步");
            }
            if (!"0".equals(device.getOnline()) && !"1".equals(device.getOnline())) {
                throw new ServiceException("平台设备状态无效，未执行同步");
            }
        }
        return devices;
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Integer> sync(String operator) throws Exception {
        List<HeadbandVO> devices = preview();
        int added = 0, updated = 0, unchanged = 0, skippedDeleted = 0;
        for (HeadbandVO device : devices) {
            List<SafetyHatInfo> existing = mapper.findIncludingDeleted(device.getHelmetSn());
            if (existing.size() > 1) throw new ServiceException("本地存在重复设备编号，请人工核对后同步");
            if (existing.isEmpty()) {
                SafetyHatInfo hat = new SafetyHatInfo();
                hat.setHatNumber(device.getHelmetSn());
                hat.setUid(device.getUid_device());
                hat.setStatus(device.getOnline());
                hat.setDelFlag("0");
                hat.setCreateBy("platform-sync");
                hat.setCreateTime(new Date());
                hat.setUpdateBy(operator);
                if (mapper.insert(hat) != 1) throw new ServiceException("真实设备导入失败");
                added++;
            } else {
                SafetyHatInfo current = existing.get(0);
                if (!"0".equals(current.getDelFlag())) { skippedDeleted++; continue; }
                if (Objects.equals(current.getStatus(), device.getOnline())
                        && (device.getUid_device() == null || Objects.equals(current.getUid(), device.getUid_device()))) {
                    unchanged++; continue;
                }
                // 稀疏更新：绝不覆盖人员、群组、绑定时间或媒体配置。
                SafetyHatInfo patch = new SafetyHatInfo();
                patch.setId(current.getId());
                patch.setStatus(device.getOnline());
                patch.setUid(device.getUid_device());
                patch.setUpdateBy(operator);
                patch.setUpdateTime(new Date());
                if (mapper.updateById(patch) != 1) throw new ServiceException("真实设备状态更新失败");
                updated++;
            }
        }
        Map<String, Integer> result = new LinkedHashMap<>();
        result.put("platformTotal", devices.size()); result.put("added", added);
        result.put("updated", updated); result.put("unchanged", unchanged);
        result.put("skippedDeleted", skippedDeleted);
        return result;
    }
}
