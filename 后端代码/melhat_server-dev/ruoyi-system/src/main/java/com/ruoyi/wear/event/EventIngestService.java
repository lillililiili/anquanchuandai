package com.ruoyi.wear.event;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Date;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.dto.IngestRequest;
import com.ruoyi.wear.event.dto.SimulateRequest;
import com.ruoyi.wear.event.mapper.WearEventInboxMapper;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.work.EventTaskMatchService;
import com.ruoyi.wear.work.WorkTaskStateMachine;

@Service
public class EventIngestService
{
    @Autowired
    private com.ruoyi.wear.device.mapper.WearProductModelMapper modelMapper;
    @Autowired
    private com.ruoyi.wear.event.mapper.WearEventActionMapper actionMapper;
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private WearEventInboxMapper inboxMapper;
    @Autowired
    private WearSiteAccountMapper siteAccountMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private EventNotifyService notifyService;
    @Autowired
    private EventTaskMatchService eventTaskMatchService;

    @Transactional(rollbackFor = Exception.class)
    public EventDto simulate(SimulateRequest request)
    {
        siteAccessService.assertCanSimulateEvent();
        if (request == null || StringUtils.isEmpty(request.getSourceEventId()) || StringUtils.isEmpty(request.getType())
                || StringUtils.isEmpty(request.getSiteId()))
        {
            throw new ServiceException("模拟事件缺少 sourceEventId、type 或 siteId", HttpStatus.BAD_REQUEST);
        }
        if (!EventStateMachine.isKnownType(request.getType()))
        {
            throw new ServiceException("不支持的事件类型", HttpStatus.BAD_REQUEST);
        }
        Long siteId = siteAccessService.parseSiteId(request.getSiteId());
        siteAccessService.assertAuthorized(siteId);
        if (request.getSourceEventId().trim().isEmpty() || request.getSourceEventId().trim().length() > 64)
            throw new ServiceException("sourceEventId 必须为 1 至 64 字符", HttpStatus.BAD_REQUEST);
        WearDevice selected = null;
        if (StringUtils.isNotEmpty(request.getDeviceId()))
        {
            try { selected = deviceMapper.selectById(Long.valueOf(request.getDeviceId())); }
            catch (NumberFormatException ex) { throw new ServiceException("设备 ID 无效", HttpStatus.BAD_REQUEST); }
            if (selected == null || !siteId.equals(selected.getSiteId()))
                throw new ServiceException("设备不存在或不属于当前厂站", HttpStatus.BAD_REQUEST);
        }
        String simulationDetail = null;
        if (StringUtils.isNotEmpty(request.getScenarioCode()))
        {
            if (selected == null) throw new ServiceException("场景测试必须指定设备", HttpStatus.BAD_REQUEST);
            com.ruoyi.wear.device.domain.WearProductModel model = modelMapper.selectById(selected.getModelId());
            simulationDetail = SimulationScenarios.detail(request, model == null ? "" : model.getTypeCode());
        }
        else if (request.getMeasurements() != null && !request.getMeasurements().isEmpty())
            throw new ServiceException("测试参数必须附带场景编码", HttpStatus.BAD_REQUEST);
        if ((request.getLat() == null) != (request.getLng() == null)
                || (request.getLat() != null && (request.getLat().abs().compareTo(new BigDecimal("90")) > 0
                || request.getLng().abs().compareTo(new BigDecimal("180")) > 0)))
            throw new ServiceException("经纬度必须成对提供且在有效范围内", HttpStatus.BAD_REQUEST);
        IngestRequest ingest = new IngestRequest();
        ingest.setSimulationDetail(simulationDetail);
        if (simulationDetail != null)
        {
            com.alibaba.fastjson2.JSONObject detail = com.alibaba.fastjson2.JSON.parseObject(simulationDetail);
            ingest.setAlarmCode(detail.getString("scenarioCode"));
            ingest.setAlarmName(detail.getString("label"));
            ingest.setAlarmDescription(detail.getString("description"));
        }
        ingest.setSource("simulator");
        ingest.setSourceEventId(request.getSourceEventId().trim());
        ingest.setType(request.getType());
        ingest.setSiteId(String.valueOf(siteId));
        ingest.setDeviceId(request.getDeviceId());
        ingest.setPersonId(request.getPersonId());
        ingest.setOccurredAt(parseTime(request.getOccurredAt()));
        ingest.setLat(request.getLat());
        ingest.setLng(request.getLng());
        ingest.setDemo(true);
        ingest.setActor(SecurityUtils.getUsername());
        if (StringUtils.isEmpty(ingest.getDeviceId()))
        {
            WearDevice demoHat = deviceMapper.selectOne(new LambdaQueryWrapper<WearDevice>()
                    .eq(WearDevice::getManufacturerCode, "MELHAT")
                    .eq(WearDevice::getSn, "MH-DEMO-001")
                    .eq(WearDevice::getSiteId, siteId)
                    .last("LIMIT 1"));
            if (demoHat != null)
            {
                ingest.setDeviceId(String.valueOf(demoHat.getId()));
            }
        }
        return ingest(ingest);
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto ingest(IngestRequest request)
    {
        if (request == null || StringUtils.isEmpty(request.getSource()) || StringUtils.isEmpty(request.getSourceEventId())
                || StringUtils.isEmpty(request.getType()) || StringUtils.isEmpty(request.getSiteId()))
        {
            throw new ServiceException("事件来源、类型和厂站不能为空", HttpStatus.BAD_REQUEST);
        }
        if (!EventStateMachine.isKnownType(request.getType()))
        {
            throw new ServiceException("不支持的事件类型", HttpStatus.BAD_REQUEST);
        }
        validateAlarmText(request.getAlarmCode(), 128);
        validateAlarmText(request.getAlarmName(), 255);
        validateAlarmText(request.getAlarmDescription(), 1000);
        Long siteId = Long.valueOf(request.getSiteId());
        WearSafetyEvent existing = eventMapper.selectOne(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSource, request.getSource())
                .eq(WearSafetyEvent::getSourceEventId, request.getSourceEventId()));
        if (existing != null)
        {
            assertSameSimulation(existing, request, siteId);
            eventMapper.bumpRepeat(existing.getId());
            return EventViews.toDto(eventMapper.selectById(existing.getId()));
        }
        Date occurred = request.getOccurredAt() == null ? new Date() : request.getOccurredAt();
        Date now = new Date();
        WearSafetyEvent row = new WearSafetyEvent();
        row.setSource(request.getSource());
        row.setSourceEventId(request.getSourceEventId());
        row.setEventType(request.getType());
        row.setAlarmCode(request.getAlarmCode());
        row.setAlarmName(request.getAlarmName());
        row.setAlarmDescription(request.getAlarmDescription());
        row.setSeverity(EventStateMachine.severityOf(request.getType()));
        row.setStatus(EventStateMachine.OPEN);
        row.setOccurredAt(occurred);
        row.setReceivedAt(now);
        row.setSiteId(siteId);
        applySnapshot(row, request, occurred);
        applyLocation(row, request);
        row.setRepeatCount(0);
        row.setEscalated(0);
        row.setRuleVersion(StringUtils.isEmpty(request.getRuleVersion()) ? "s5-1" : request.getRuleVersion());
        row.setFenceId(request.getFenceId());
        row.setFenceAction(request.getFenceAction());
        row.setDemo(request.isDemo() ? 1 : 0);
        row.setTaskMatch(WorkTaskStateMachine.MATCH_NONE);
        row.setVersion(1);
        String actor = StringUtils.isEmpty(request.getActor()) ? "system" : request.getActor();
        row.setCreateBy(actor);
        row.setCreateTime(now);
        row.setUpdateBy(actor);
        row.setUpdateTime(now);
        try
        {
            eventMapper.insert(row);
        }
        catch (DataIntegrityViolationException ex)
        {
            WearSafetyEvent raced = eventMapper.selectOne(new LambdaQueryWrapper<WearSafetyEvent>()
                    .eq(WearSafetyEvent::getSource, request.getSource())
                    .eq(WearSafetyEvent::getSourceEventId, request.getSourceEventId()));
            if (raced == null)
            {
                throw ex;
            }
            assertSameSimulation(raced, request, siteId);
            eventMapper.bumpRepeat(raced.getId());
            return EventViews.toDto(eventMapper.selectById(raced.getId()));
        }
        if (request.getSimulationDetail() != null && request.isDemo() && "simulator".equals(request.getSource()))
        {
            com.ruoyi.wear.event.domain.WearEventAction action = new com.ruoyi.wear.event.domain.WearEventAction();
            action.setEventId(row.getId());
            action.setAction("simulate");
            action.setActor(actor);
            action.setReason(request.getSimulationDetail());
            action.setToStatus(EventStateMachine.OPEN);
            action.setCreateTime(now);
            actionMapper.insert(action);
        }
        fillInbox(row);
        eventTaskMatchService.applyOnInsert(row);
        notifyService.notifyAfterCommit(row);
        return EventViews.toDto(eventMapper.selectById(row.getId()));
    }

    private void assertSameSimulation(WearSafetyEvent existing, IngestRequest request, Long siteId)
    {
        if ("simulator".equals(request.getSource())
                && (!siteId.equals(existing.getSiteId()) || !request.getType().equals(existing.getEventType())
                || (StringUtils.isNotEmpty(request.getDeviceId())
                && !request.getDeviceId().equals(String.valueOf(existing.getDeviceId())))))
            throw new ServiceException("重复事件标识已用于其他厂站、设备或事件类型", HttpStatus.CONFLICT);
    }

    private void validateAlarmText(String text, int limit)
    {
        if (text != null && text.length() > limit)
            throw new ServiceException("告警描述字段超过长度限制", HttpStatus.BAD_REQUEST);
    }

    private void applySnapshot(WearSafetyEvent row, IngestRequest request, Date occurred)
    {
        WearDevice device = null;
        if (StringUtils.isNotEmpty(request.getDeviceId()))
        {
            device = deviceMapper.selectById(Long.valueOf(request.getDeviceId()));
            if (device != null && device.getSiteId() != null && !device.getSiteId().equals(row.getSiteId()))
            {
                throw new ServiceException("设备不属于该厂站", HttpStatus.BAD_REQUEST);
            }
        }
        WearAssignment assignment = null;
        if (device != null)
        {
            assignment = assignmentMapper.findAtDeviceTime(device.getId(), occurred);
        }
        if (assignment != null)
        {
            WearPerson person = personMapper.selectById(assignment.getPersonId());
            WearDevice held = deviceMapper.selectById(assignment.getDeviceId());
            row.setPersonId(assignment.getPersonId());
            if (person != null)
            {
                row.setPersonCode(person.getPersonCode());
                row.setPersonName(person.getName());
            }
            if (held != null)
            {
                row.setDeviceId(held.getId());
                row.setSn(held.getSn());
            }
            return;
        }
        row.setPersonId(null);
        row.setPersonCode(null);
        row.setPersonName(null);
        if (device != null)
        {
            row.setDeviceId(device.getId());
            row.setSn(device.getSn());
        }
    }

    private void applyLocation(WearSafetyEvent row, IngestRequest request)
    {
        BigDecimal lat = request.getLat();
        BigDecimal lng = request.getLng();
        row.setLocationLat(lat);
        row.setLocationLng(lng);
        if (StringUtils.isNotEmpty(request.getLocationQuality()))
        {
            row.setLocationQuality(request.getLocationQuality());
        }
        else if (lat != null && lng != null)
        {
            row.setLocationQuality("ok");
        }
        else
        {
            row.setLocationQuality("unknown");
        }
    }

    private void fillInbox(WearSafetyEvent row)
    {
        List<WearSiteAccount> grants = siteAccountMapper.selectList(new LambdaQueryWrapper<WearSiteAccount>()
                .eq(WearSiteAccount::getSiteId, row.getSiteId())
                .eq(WearSiteAccount::getStatus, "0"));
        for (WearSiteAccount grant : grants)
        {
            if (grant.getUserId() != null)
            {
                inboxMapper.insertIgnore(grant.getUserId(), row.getId());
            }
        }
    }

    private Date parseTime(String raw)
    {
        if (StringUtils.isEmpty(raw))
        {
            return new Date();
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
            throw new ServiceException("发生时间格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
