package com.ruoyi.wear.admin;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.location.domain.WearGeoFence;
import com.ruoyi.wear.location.mapper.WearGeoFenceMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.domain.WearPersonSite;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.person.mapper.WearPersonSiteMapper;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;

@Service
public class AdminOverviewService
{
    @Autowired private SiteAccessService siteAccessService;
    @Autowired private WearPersonSiteMapper personSiteMapper;
    @Autowired private WearPersonMapper personMapper;
    @Autowired private WearDeviceMapper deviceMapper;
    @Autowired private WearWorkTaskMapper taskMapper;
    @Autowired private WearGeoFenceMapper fenceMapper;
    @Autowired private WearSafetyEventMapper eventMapper;

    public Map<String, Object> overview()
    {
        List<Long> siteIds = siteAccessService.listScopeSiteIds();
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("people", people(siteIds));
        result.put("devices", devices(siteIds));
        result.put("tasks", tasks(siteIds));
        result.put("fences", fences(siteIds));
        result.put("events", events(siteIds));
        result.put("eventTrend", eventTrend(siteIds));
        return result;
    }

    private Map<String, Long> people(List<Long> siteIds)
    {
        Set<Long> personIds = new LinkedHashSet<Long>();
        if (!siteIds.isEmpty())
        {
            List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                    .in(WearPersonSite::getSiteId, siteIds).eq(WearPersonSite::getStatus, "0"));
            for (WearPersonSite grant : grants) personIds.add(grant.getPersonId());
        }
        long active = 0;
        if (!personIds.isEmpty())
        {
            active = personMapper.selectCount(new LambdaQueryWrapper<WearPerson>()
                    .in(WearPerson::getId, personIds).eq(WearPerson::getStatus, "0"));
        }
        Map<String, Long> map = new LinkedHashMap<String, Long>();
        map.put("total", Long.valueOf(personIds.size()));
        map.put("active", active);
        return map;
    }

    private Map<String, Long> devices(List<Long> siteIds)
    {
        Map<String, Long> map = new LinkedHashMap<String, Long>();
        long total = countDevices(siteIds, null);
        map.put("total", total);
        map.put("inStock", countDevices(siteIds, "in_stock"));
        map.put("issued", countDevices(siteIds, "issued"));
        map.put("maintenance", countDevices(siteIds, "maintenance"));
        map.put("disabled", countDevices(siteIds, "disabled") + countDevices(siteIds, "scrapped"));
        return map;
    }

    private long countDevices(List<Long> siteIds, String status)
    {
        if (siteIds.isEmpty()) return 0;
        LambdaQueryWrapper<WearDevice> query = new LambdaQueryWrapper<WearDevice>().in(WearDevice::getSiteId, siteIds);
        if (status != null) query.eq(WearDevice::getAssetStatus, status);
        return deviceMapper.selectCount(query);
    }

    private Map<String, Long> tasks(List<Long> siteIds)
    {
        Map<String, Long> map = new LinkedHashMap<String, Long>();
        long draft = countTasks(siteIds, "draft");
        long ready = countTasks(siteIds, "ready");
        long progress = countTasks(siteIds, "in_progress");
        long paused = countTasks(siteIds, "paused");
        map.put("draft", draft); map.put("ready", ready); map.put("inProgress", progress); map.put("paused", paused);
        map.put("active", draft + ready + progress + paused);
        return map;
    }

    private long countTasks(List<Long> siteIds, String status)
    {
        if (siteIds.isEmpty()) return 0;
        return taskMapper.selectCount(new LambdaQueryWrapper<WearWorkTask>()
                .in(WearWorkTask::getSiteId, siteIds).eq(WearWorkTask::getStatus, status));
    }

    private Map<String, Long> fences(List<Long> siteIds)
    {
        Map<String, Long> map = new LinkedHashMap<String, Long>();
        if (siteIds.isEmpty()) { map.put("total", 0L); map.put("enabled", 0L); return map; }
        map.put("total", Long.valueOf(fenceMapper.selectCount(new LambdaQueryWrapper<WearGeoFence>().in(WearGeoFence::getSiteId, siteIds))));
        map.put("enabled", Long.valueOf(fenceMapper.selectCount(new LambdaQueryWrapper<WearGeoFence>()
                .in(WearGeoFence::getSiteId, siteIds).eq(WearGeoFence::getEnabled, 1))));
        return map;
    }

    private Map<String, Long> events(List<Long> siteIds)
    {
        Map<String, Long> map = new LinkedHashMap<String, Long>();
        if (siteIds.isEmpty()) { map.put("open", 0L); map.put("last7Days", 0L); return map; }
        long open = eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .in(WearSafetyEvent::getSiteId, siteIds).ne(WearSafetyEvent::getStatus, "closed"));
        Date from = dayStart(-6);
        long recent = eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .in(WearSafetyEvent::getSiteId, siteIds).ge(WearSafetyEvent::getOccurredAt, from));
        map.put("open", open); map.put("last7Days", recent);
        return map;
    }

    private List<Map<String, Object>> eventTrend(List<Long> siteIds)
    {
        List<Map<String, Object>> result = new ArrayList<Map<String, Object>>();
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd");
        Map<String, Long> counts = new LinkedHashMap<String, Long>();
        for (int i = -6; i <= 0; i++) counts.put(format.format(dayStart(i)), 0L);
        if (!siteIds.isEmpty())
        {
            List<WearSafetyEvent> rows = eventMapper.selectList(new LambdaQueryWrapper<WearSafetyEvent>()
                    .select(WearSafetyEvent::getOccurredAt).in(WearSafetyEvent::getSiteId, siteIds)
                    .ge(WearSafetyEvent::getOccurredAt, dayStart(-6)));
            for (WearSafetyEvent row : rows)
            {
                if (row.getOccurredAt() == null) continue;
                String key = format.format(row.getOccurredAt());
                if (counts.containsKey(key)) counts.put(key, counts.get(key) + 1L);
            }
        }
        for (Map.Entry<String, Long> entry : counts.entrySet())
        {
            Map<String, Object> point = new LinkedHashMap<String, Object>();
            point.put("date", entry.getKey()); point.put("count", entry.getValue()); result.add(point);
        }
        return result;
    }

    private Date dayStart(int offset)
    {
        Calendar calendar = Calendar.getInstance();
        calendar.add(Calendar.DATE, offset);
        calendar.set(Calendar.HOUR_OF_DAY, 0); calendar.set(Calendar.MINUTE, 0);
        calendar.set(Calendar.SECOND, 0); calendar.set(Calendar.MILLISECOND, 0);
        return calendar.getTime();
    }
}
