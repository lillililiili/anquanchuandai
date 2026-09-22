package com.ruoyi.wear.location;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.location.domain.WearGeoFence;
import com.ruoyi.wear.location.domain.WearGeoFencePerson;
import com.ruoyi.wear.location.dto.GeoFenceDto;
import com.ruoyi.wear.location.mapper.WearGeoFenceMapper;
import com.ruoyi.wear.location.mapper.WearGeoFencePersonMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.mapper.WearPersonMapper;

@Service
public class FenceService
{
    @Autowired
    private WearGeoFenceMapper fenceMapper;
    @Autowired
    private WearGeoFencePersonMapper fencePersonMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private GeofenceEngine geofenceEngine;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired private com.ruoyi.wear.person.mapper.WearPersonSiteMapper personSiteMapper;
    @Value("${melhat.demo-mode:false}")
    private boolean demoMode;
    @Value("${spring.profiles.active:}")
    private String activeProfile;

    public WearPage<GeoFenceDto> page(int current, int size, String name, String enabled)
    {
        siteAccessService.requireLogin();
        int safeCurrent = current < 1 ? 1 : current;
        int safeSize = size < 1 ? 10 : Math.min(size, 100);
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return WearPage.of(Collections.<GeoFenceDto>emptyList(), 0, safeCurrent, safeSize);
        }
        LambdaQueryWrapper<WearGeoFence> query = new LambdaQueryWrapper<WearGeoFence>()
                .in(WearGeoFence::getSiteId, scope)
                .like(StringUtils.isNotEmpty(name), WearGeoFence::getName, name == null ? null : name.trim())
                .orderByDesc(WearGeoFence::getId);
        if (StringUtils.isNotEmpty(enabled))
        {
            query.eq(WearGeoFence::getEnabled,
                    "true".equalsIgnoreCase(enabled) || "1".equals(enabled) ? 1 : 0);
        }
        IPage<WearGeoFence> page = fenceMapper.selectPage(new Page<WearGeoFence>(safeCurrent, safeSize), query);
        List<GeoFenceDto> records = new ArrayList<GeoFenceDto>();
        for (WearGeoFence row : page.getRecords())
        {
            records.add(toDto(row));
        }
        return WearPage.of(records, page.getTotal(), safeCurrent, safeSize);
    }

    public GeoFenceDto detail(Long id)
    {
        return toDto(requireReadable(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public GeoFenceDto create(Map<String, Object> body)
    {
        siteAccessService.assertCanWriteDevice();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        validateWrite(body, null, siteId);
        String name = str(body, "name");
        List<Map<String, Object>> polygon = polygonOf(body.get("polygon"));
        if (StringUtils.isEmpty(name) || polygon.size() < 3)
        {
            throw new ServiceException("名称和多边形至少三个点", HttpStatus.BAD_REQUEST);
        }
        WearGeoFence row = new WearGeoFence();
        row.setSiteId(siteId);
        row.setName(name.trim());
        row.setPolygonJson(JSON.toJSONString(polygon));
        row.setEnabled(bool(body, "enabled", true) ? 1 : 0);
        String mode = str(body, "applyMode");
        row.setApplyMode("persons".equals(mode) ? "persons" : "all_site");
        row.setTimeStart(str(body, "timeStart"));
        row.setTimeEnd(str(body, "timeEnd"));
        row.setEnterEnabled(bool(body, "enterEnabled", true) ? 1 : 0);
        row.setLeaveEnabled(bool(body, "leaveEnabled", true) ? 1 : 0);
        Integer debounce = intVal(body, "debounceSeconds");
        row.setDebounceSeconds(debounce == null ? 60 : debounce);
        row.setRuleVersion(1);
        row.setDemo(0);
        row.setVersion(1);
        String actor = SecurityUtils.getUsername();
        row.setCreateBy(actor);
        row.setCreateTime(new Date());
        row.setUpdateBy(actor);
        row.setUpdateTime(new Date());
        fenceMapper.insert(row);
        replacePersons(row.getId(), stringList(body, "personIds"));
        return toDto(fenceMapper.selectById(row.getId()));
    }

    @Transactional(rollbackFor = Exception.class)
    public GeoFenceDto update(Long id, Map<String, Object> body)
    {
        siteAccessService.assertCanWriteDevice();
        WearGeoFence row = requireReadable(id);
        validateWrite(body, row, row.getSiteId());
        Integer version = intVal(body, "version");
        if (version == null || !version.equals(row.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        boolean geometryChanged = false;
        if (body.containsKey("enabled")) row.setEnabled(bool(body, "enabled", true) ? 1 : 0);
        if (body.containsKey("name") && StringUtils.isNotEmpty(str(body, "name")))
        {
            row.setName(str(body, "name").trim());
        }
        if (body.containsKey("polygon"))
        {
            List<Map<String, Object>> polygon = polygonOf(body.get("polygon"));
            if (polygon.size() < 3)
            {
                throw new ServiceException("多边形至少三个点", HttpStatus.BAD_REQUEST);
            }
            String json = JSON.toJSONString(polygon);
            if (!json.equals(row.getPolygonJson()))
            {
                geometryChanged = true;
            }
            row.setPolygonJson(json);
        }
        boolean applyModeChanged = false;
        if (body.containsKey("applyMode"))
        {
            String nextMode = "persons".equals(str(body, "applyMode")) ? "persons" : "all_site";
            applyModeChanged = !nextMode.equals(row.getApplyMode());
            row.setApplyMode(nextMode);
        }
        if (body.containsKey("timeStart") || body.containsKey("timeEnd")
                || body.containsKey("enterEnabled") || body.containsKey("leaveEnabled")
                || body.containsKey("debounceSeconds") || body.containsKey("personIds")
                || geometryChanged || applyModeChanged)
        {
            row.setRuleVersion((row.getRuleVersion() == null ? 1 : row.getRuleVersion()) + 1);
        }
        if (body.containsKey("timeStart"))
        {
            row.setTimeStart(str(body, "timeStart"));
        }
        if (body.containsKey("timeEnd"))
        {
            row.setTimeEnd(str(body, "timeEnd"));
        }
        if (body.containsKey("enterEnabled"))
        {
            row.setEnterEnabled(bool(body, "enterEnabled", true) ? 1 : 0);
        }
        if (body.containsKey("leaveEnabled"))
        {
            row.setLeaveEnabled(bool(body, "leaveEnabled", true) ? 1 : 0);
        }
        if (body.containsKey("debounceSeconds") && intVal(body, "debounceSeconds") != null)
        {
            row.setDebounceSeconds(intVal(body, "debounceSeconds"));
        }
        if (body.containsKey("personIds"))
        {
            replacePersons(id, stringList(body, "personIds"));
        }
        row.setVersion(row.getVersion() + 1);
        row.setUpdateBy(SecurityUtils.getUsername());
        row.setUpdateTime(new Date());
        fenceMapper.updateById(row);
        return toDto(fenceMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public GeoFenceDto setEnabled(Long id, Map<String, Object> body)
    {
        siteAccessService.assertCanWriteDevice();
        WearGeoFence row = requireReadable(id);
        Integer version = intVal(body, "version");
        if (version == null || !version.equals(row.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        row.setEnabled(bool(body, "enabled", true) ? 1 : 0);
        row.setVersion(row.getVersion() + 1);
        row.setUpdateBy(SecurityUtils.getUsername());
        row.setUpdateTime(new Date());
        fenceMapper.updateById(row);
        return toDto(fenceMapper.selectById(id));
    }

    public Map<String, Object> evaluate(Map<String, Object> body)
    {
        siteAccessService.assertCanWriteDevice();
        if (!demoMode || (activeProfile != null && activeProfile.contains("prod")))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        Long personId = parseLong(str(body, "personId"));
        WearPerson person = personId == null ? null : personMapper.selectById(personId);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        BigDecimal lat = decimal(body.get("lat"));
        BigDecimal lng = decimal(body.get("lng"));
        if (lat == null || lng == null)
        {
            throw new ServiceException("坐标不能为空", HttpStatus.BAD_REQUEST);
        }
        WearDevice device = null;
        if (StringUtils.isNotEmpty(str(body, "deviceId")))
        {
            device = deviceMapper.selectById(parseLong(str(body, "deviceId")));
        }
        Date now = new Date();
        int fired = geofenceEngine.evaluate(siteId, personId, device, now, lat, lng, TelemetryFreshness.OK, now, true);
        Map<String, Object> data = new HashMap<String, Object>();
        data.put("fired", Integer.valueOf(fired));
        data.put("demo", Boolean.TRUE);
        return data;
    }

    private WearGeoFence requireReadable(Long id)
    {
        WearGeoFence row = fenceMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(row.getSiteId());
        return row;
    }

    private GeoFenceDto toDto(WearGeoFence row)
    {
        GeoFenceDto dto = new GeoFenceDto();
        dto.setId(String.valueOf(row.getId()));
        dto.setSiteId(String.valueOf(row.getSiteId()));
        dto.setName(row.getName());
        dto.setPolygon(polygonOf(JSON.parse(row.getPolygonJson())));
        dto.setEnabled(row.getEnabled() != null && row.getEnabled().intValue() == 1);
        dto.setApplyMode(row.getApplyMode());
        dto.setTimeStart(row.getTimeStart());
        dto.setTimeEnd(row.getTimeEnd());
        dto.setEnterEnabled(row.getEnterEnabled() == null || row.getEnterEnabled().intValue() == 1);
        dto.setLeaveEnabled(row.getLeaveEnabled() == null || row.getLeaveEnabled().intValue() == 1);
        dto.setDebounceSeconds(row.getDebounceSeconds());
        dto.setRuleVersion(row.getRuleVersion());
        dto.setDemo(row.getDemo() != null && row.getDemo().intValue() == 1);
        dto.setVersion(row.getVersion());
        List<String> ids = new ArrayList<String>();
        List<WearGeoFencePerson> persons = fencePersonMapper.selectList(new LambdaQueryWrapper<WearGeoFencePerson>()
                .eq(WearGeoFencePerson::getFenceId, row.getId()));
        for (WearGeoFencePerson person : persons)
        {
            ids.add(String.valueOf(person.getPersonId()));
        }
        dto.setPersonIds(ids);
        return dto;
    }

    private void replacePersons(Long fenceId, List<String> personIds)
    {
        fencePersonMapper.delete(new LambdaQueryWrapper<WearGeoFencePerson>().eq(WearGeoFencePerson::getFenceId, fenceId));
        for (String id : personIds)
        {
            Long personId = parseLong(id);
            if (personId == null)
            {
                continue;
            }
            WearGeoFencePerson row = new WearGeoFencePerson();
            row.setFenceId(fenceId);
            row.setPersonId(personId);
            fencePersonMapper.insert(row);
        }
    }

    private void validateWrite(Map<String,Object> body, WearGeoFence previous, Long siteId)
    {
        String name = body.containsKey("name") ? str(body,"name") : previous == null ? null : previous.getName();
        if (name == null || name.trim().isEmpty() || name.length() > 100)
            throw new ServiceException("请填写不超过 100 字的围栏名称", 400);
        if (body.containsKey("polygon")) {
            List<Map<String,Object>> points = polygonOf(body.get("polygon"));
            if (points.size() < 3 || points.size() > 100)
                throw new ServiceException("围栏需要 3–100 个顶点", 400);
            java.util.Set<String> distinct = new java.util.HashSet<>();
            double area = 0;
            for (int i=0; i<points.size(); i++) {
                BigDecimal lat = (BigDecimal) points.get(i).get("lat"), lng = (BigDecimal) points.get(i).get("lng");
                if (lat == null || lng == null || lat.abs().doubleValue() > 85 || lng.abs().doubleValue() > 180)
                    throw new ServiceException("围栏坐标无效", 400);
                distinct.add(lat.stripTrailingZeros()+":"+lng.stripTrailingZeros());
            }
            for (int i=0; i<points.size(); i++) {
                Map<String,Object> a=points.get(i), b=points.get((i+1)%points.size());
                area += ((BigDecimal)a.get("lng")).doubleValue()*((BigDecimal)b.get("lat")).doubleValue()
                    - ((BigDecimal)b.get("lng")).doubleValue()*((BigDecimal)a.get("lat")).doubleValue();
            }
            if (distinct.size()<3 || Math.abs(area)<1e-12) throw new ServiceException("围栏顶点不能重合或围成直线",400);
        }
        boolean enter = bool(body,"enterEnabled",previous == null || previous.getEnterEnabled()==1);
        boolean leave = bool(body,"leaveEnabled",previous == null || previous.getLeaveEnabled()==1);
        if (!enter && !leave) throw new ServiceException("请至少选择一种触发方向",400);
        Integer delay = body.containsKey("debounceSeconds") ? intVal(body,"debounceSeconds") : previous == null ? 60 : previous.getDebounceSeconds();
        if (delay == null || delay < 0 || delay > 86400) throw new ServiceException("防抖时间应为 0–86400 秒",400);
        String start=body.containsKey("timeStart") ? str(body,"timeStart") : previous == null ? null : previous.getTimeStart();
        String end=body.containsKey("timeEnd") ? str(body,"timeEnd") : previous == null ? null : previous.getTimeEnd();
        if (StringUtils.isEmpty(start) != StringUtils.isEmpty(end)) throw new ServiceException("请完整选择生效时段",400);
        for (String time : new String[]{start,end}) if (StringUtils.isNotEmpty(time) && !time.matches("([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?"))
            throw new ServiceException("生效时段格式无效",400);
        String mode=body.containsKey("applyMode") ? str(body,"applyMode") : previous == null ? "all_site" : previous.getApplyMode();
        if ("persons".equals(mode) && (body.containsKey("personIds") || previous == null)) {
            List<String> ids=stringList(body,"personIds");
            if (ids.isEmpty()) throw new ServiceException("请选择适用人员",400);
            for (String id : ids) {
                Long personId=parseLong(id);
                if (personId == null || personMapper.selectById(personId)==null || personSiteMapper.selectCount(
                    new LambdaQueryWrapper<com.ruoyi.wear.person.domain.WearPersonSite>()
                    .eq(com.ruoyi.wear.person.domain.WearPersonSite::getPersonId,personId)
                    .eq(com.ruoyi.wear.person.domain.WearPersonSite::getSiteId,siteId)
                    .eq(com.ruoyi.wear.person.domain.WearPersonSite::getStatus,"0"))==0)
                    throw new ServiceException("所选人员不属于此围栏厂站",403);
            }
        }
    }

    private List<Map<String, Object>> polygonOf(Object raw)
    {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        if (raw instanceof Map)
        {
            Map<?, ?> geo = (Map<?, ?>) raw;
            Object coords = geo.get("coordinates");
            if (coords instanceof List && !((List<?>) coords).isEmpty())
            {
                Object ring = ((List<?>) coords).get(0);
                return polygonOf(ring);
            }
            return out;
        }
        if (!(raw instanceof List))
        {
            return out;
        }
        for (Object item : (List<?>) raw)
        {
            Object lng = null;
            Object lat = null;
            if (item instanceof Map)
            {
                Map<?, ?> map = (Map<?, ?>) item;
                lng = map.get("lng") != null ? map.get("lng") : map.get("longitude");
                lat = map.get("lat") != null ? map.get("lat") : map.get("latitude");
            }
            else if (item instanceof List && ((List<?>) item).size() >= 2)
            {
                lng = ((List<?>) item).get(0);
                lat = ((List<?>) item).get(1);
            }
            if (lng == null || lat == null)
            {
                continue;
            }
            Map<String, Object> point = new HashMap<String, Object>();
            point.put("lng", decimal(lng));
            point.put("lat", decimal(lat));
            out.add(point);
        }
        return out;
    }

    private static String str(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return null;
        }
        String value = String.valueOf(body.get(key));
        return "null".equals(value) ? null : value;
    }

    private static boolean bool(Map<String, Object> body, String key, boolean def)
    {
        if (body == null || body.get(key) == null)
        {
            return def;
        }
        Object raw = body.get(key);
        if (raw instanceof Boolean)
        {
            return ((Boolean) raw).booleanValue();
        }
        return "true".equalsIgnoreCase(String.valueOf(raw)) || "1".equals(String.valueOf(raw));
    }

    private static Integer intVal(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return null;
        }
        try
        {
            return Integer.valueOf(String.valueOf(body.get(key)));
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private static Long parseLong(String raw)
    {
        if (StringUtils.isEmpty(raw))
        {
            return null;
        }
        try
        {
            return Long.valueOf(raw.trim());
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private static List<String> stringList(Map<String, Object> body, String key)
    {
        List<String> values = new ArrayList<String>();
        if (body == null || !(body.get(key) instanceof List))
        {
            return values;
        }
        for (Object item : (List<?>) body.get(key))
        {
            if (item != null)
            {
                values.add(String.valueOf(item));
            }
        }
        return values;
    }

    private static BigDecimal decimal(Object raw)
    {
        if (raw == null)
        {
            return null;
        }
        try
        {
            return new BigDecimal(String.valueOf(raw));
        }
        catch (Exception ex)
        {
            return null;
        }
    }
}
