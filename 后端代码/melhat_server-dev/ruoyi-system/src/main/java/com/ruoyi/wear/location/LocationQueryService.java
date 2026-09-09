package com.ruoyi.wear.location;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.helmet.domain.WearDeviceSample;
import com.ruoyi.wear.helmet.mapper.WearDeviceSampleMapper;
import com.ruoyi.wear.location.dto.PersonLocationDto;
import com.ruoyi.wear.location.dto.TrackPointDto;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.domain.WearPersonSite;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.person.mapper.WearPersonSiteMapper;

@Service
public class LocationQueryService
{
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired
    private WearPersonSiteMapper personSiteMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private WearDeviceSampleMapper sampleMapper;
    @Value("${melhat.telemetry.stale-after-seconds:180}")
    private int staleAfterSeconds;

    public WearPage<PersonLocationDto> page(int current, int size)
    {
        siteAccessService.requireLogin();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        if (size > 100)
        {
            size = 100;
        }
        if (current < 1)
        {
            current = 1;
        }
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getSiteId, siteId).eq(WearPersonSite::getStatus, "0"));
        List<Long> personIds = new ArrayList<Long>();
        for (WearPersonSite grant : grants)
        {
            personIds.add(grant.getPersonId());
        }
        if (personIds.isEmpty())
        {
            return WearPage.of(Collections.<PersonLocationDto>emptyList(), 0, current, size);
        }
        IPage<WearPerson> page = personMapper.selectPage(new Page<WearPerson>(current, size),
                new LambdaQueryWrapper<WearPerson>().in(WearPerson::getId, personIds).eq(WearPerson::getDelFlag, "0")
                        .orderByAsc(WearPerson::getId));
        List<PersonLocationDto> records = new ArrayList<PersonLocationDto>();
        Date now = new Date();
        for (WearPerson person : page.getRecords())
        {
            records.add(toLocation(person, siteId, now));
        }
        return WearPage.of(records, page.getTotal(), current, size);
    }

    public PersonLocationDto detail(Long personId)
    {
        WearPerson person = requirePerson(personId);
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        if (personSiteMapper.selectCount(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId)
                .eq(WearPersonSite::getSiteId, siteId)
                .eq(WearPersonSite::getStatus, "0")) == 0)
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        return toLocation(person, siteId, new Date());
    }

    public WearPage<TrackPointDto> tracks(Long personId, String fromRaw, String toRaw, int current, int size)
    {
        requirePerson(personId);
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        if (personSiteMapper.selectCount(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId)
                .eq(WearPersonSite::getSiteId, siteId)
                .eq(WearPersonSite::getStatus, "0")) == 0)
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        Date from = parseTime(fromRaw, true);
        Date to = parseTime(toRaw, true);
        if (to.before(from))
        {
            throw new ServiceException("时间范围无效", HttpStatus.BAD_REQUEST);
        }
        List<WearAssignment> assignments = assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getPersonId, personId)
                .le(WearAssignment::getIssuedAt, to)
                .and(q -> q.isNull(WearAssignment::getReturnedAt).or().gt(WearAssignment::getReturnedAt, from)));
        Set<Long> helmetIds = new HashSet<Long>();
        for (WearAssignment assignment : assignments)
        {
            if (isHelmet(assignment.getDeviceId()))
            {
                helmetIds.add(assignment.getDeviceId());
            }
        }
        if (helmetIds.isEmpty())
        {
            return WearPage.of(Collections.<TrackPointDto>emptyList(), 0, current, size);
        }
        List<WearDeviceSample> samples = sampleMapper.selectList(new LambdaQueryWrapper<WearDeviceSample>()
                .in(WearDeviceSample::getDeviceId, helmetIds)
                .ge(WearDeviceSample::getOccurredAt, from)
                .le(WearDeviceSample::getOccurredAt, to)
                .isNotNull(WearDeviceSample::getLat)
                .isNotNull(WearDeviceSample::getLng)
                .orderByAsc(WearDeviceSample::getOccurredAt));
        List<TrackPointDto> points = new ArrayList<TrackPointDto>();
        for (WearDeviceSample sample : samples)
        {
            if (!heldAt(assignments, sample.getDeviceId(), sample.getOccurredAt()))
            {
                continue;
            }
            WearDevice device = deviceMapper.selectById(sample.getDeviceId());
            TrackPointDto point = new TrackPointDto();
            point.setOccurredAt(sample.getOccurredAt());
            point.setLat(sample.getLat());
            point.setLng(sample.getLng());
            point.setLocationQuality(sample.getLocationQuality() == null
                    ? PersonLocationPolicy.qualityWithoutFix() : sample.getLocationQuality());
            point.setDeviceId(String.valueOf(sample.getDeviceId()));
            point.setSn(device == null ? null : device.getSn());
            points.add(point);
        }
        if (points.size() > 500)
        {
            points = thin(points, 500);
        }
        if (size < 1)
        {
            size = 10;
        }
        if (current < 1)
        {
            current = 1;
        }
        int fromIdx = Math.min((current - 1) * size, points.size());
        int toIdx = Math.min(fromIdx + size, points.size());
        return WearPage.of(points.subList(fromIdx, toIdx), points.size(), current, size);
    }

    private PersonLocationDto toLocation(WearPerson person, Long siteId, Date now)
    {
        PersonLocationDto dto = new PersonLocationDto();
        dto.setPersonId(String.valueOf(person.getId()));
        dto.setPersonCode(person.getPersonCode());
        dto.setPersonName(person.getName());
        dto.setFloor(PersonLocationPolicy.floor());
        dto.setFloorSource(PersonLocationPolicy.floorSource());
        dto.setDemo("demo".equals(person.getCreateBy()));
        dto.setSource(PersonLocationPolicy.source(false));
        dto.setLocationQuality(PersonLocationPolicy.qualityWithoutFix());
        dto.setConnectionQuality(TelemetryFreshness.UNKNOWN);
        WearAssignment helmet = currentHelmet(person.getId(), siteId);
        if (helmet == null)
        {
            return dto;
        }
        WearDevice device = deviceMapper.selectById(helmet.getDeviceId());
        if (device == null)
        {
            return dto;
        }
        dto.setDeviceId(String.valueOf(device.getId()));
        dto.setSn(device.getSn());
        dto.setSource(PersonLocationPolicy.source(true));
        WearDeviceSample sample = sampleMapper.selectOne(new LambdaQueryWrapper<WearDeviceSample>()
                .eq(WearDeviceSample::getDeviceId, device.getId())
                .isNotNull(WearDeviceSample::getLat)
                .isNotNull(WearDeviceSample::getLng)
                .orderByDesc(WearDeviceSample::getOccurredAt)
                .last("LIMIT 1"));
        if (sample == null)
        {
            dto.setConnectionQuality(TelemetryFreshness.connectionQuality(device.getLastReportedAt(), now, staleAfterSeconds));
            return dto;
        }
        dto.setLat(sample.getLat());
        dto.setLng(sample.getLng());
        dto.setOccurredAt(sample.getOccurredAt());
        dto.setLocationQuality(qualityAt(sample.getOccurredAt(), sample.getLocationQuality(), now));
        dto.setConnectionQuality(TelemetryFreshness.connectionQuality(sample.getOccurredAt(), now, staleAfterSeconds));
        return dto;
    }

    private WearAssignment currentHelmet(Long personId, Long siteId)
    {
        List<WearAssignment> rows = assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getPersonId, personId)
                .eq(WearAssignment::getSiteId, siteId)
                .isNull(WearAssignment::getReturnedAt));
        for (WearAssignment row : rows)
        {
            if (isHelmet(row.getDeviceId()))
            {
                return row;
            }
        }
        return null;
    }

    private boolean isHelmet(Long deviceId)
    {
        WearDevice device = deviceMapper.selectById(deviceId);
        if (device == null || device.getModelId() == null)
        {
            return false;
        }
        WearProductModel model = modelMapper.selectById(device.getModelId());
        return model != null && PersonLocationPolicy.canContributeLocation(model.getTypeCode());
    }

    private boolean heldAt(List<WearAssignment> assignments, Long deviceId, Date at)
    {
        for (WearAssignment row : assignments)
        {
            if (!deviceId.equals(row.getDeviceId()))
            {
                continue;
            }
            if (row.getIssuedAt() != null && at.before(row.getIssuedAt()))
            {
                continue;
            }
            if (row.getReturnedAt() != null && !at.before(row.getReturnedAt()))
            {
                continue;
            }
            return true;
        }
        return false;
    }

    private String qualityAt(Date occurredAt, String stored, Date now)
    {
        if (!TelemetryFreshness.OK.equals(stored))
        {
            return stored == null ? TelemetryFreshness.UNKNOWN : stored;
        }
        return TelemetryFreshness.connectionQuality(occurredAt, now, staleAfterSeconds);
    }

    private List<TrackPointDto> thin(List<TrackPointDto> points, int max)
    {
        List<TrackPointDto> out = new ArrayList<TrackPointDto>();
        int n = points.size();
        for (int i = 0; i < max; i++)
        {
            int idx = (int) Math.round(i * (n - 1.0) / (max - 1.0));
            out.add(points.get(idx));
        }
        return out;
    }

    private WearPerson requirePerson(Long id)
    {
        siteAccessService.requireLogin();
        WearPerson person = personMapper.selectById(id);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        return person;
    }

    private Date parseTime(String raw, boolean required)
    {
        if (StringUtils.isEmpty(raw))
        {
            if (required)
            {
                throw new ServiceException("时间不能为空", HttpStatus.BAD_REQUEST);
            }
            return null;
        }
        try
        {
            return Date.from(OffsetDateTime.parse(raw).toInstant());
        }
        catch (Exception ignored)
        {
        }
        try
        {
            return Date.from(Instant.parse(raw));
        }
        catch (Exception ex)
        {
            throw new ServiceException("时间格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
