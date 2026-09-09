package com.ruoyi.wear.call;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.domain.WearIdempotency;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.assignment.mapper.WearIdempotencyMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.call.domain.WearCallSession;
import com.ruoyi.wear.call.dto.CallCredentialsDto;
import com.ruoyi.wear.call.dto.CallDto;
import com.ruoyi.wear.call.mapper.WearCallSessionMapper;
import com.ruoyi.wear.device.DeviceCapability;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.helmet.TelemetryFreshness;

@Service
public class CallService
{
    @Autowired
    private WearCallSessionMapper callMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private WearIdempotencyMapper idempotencyMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private CallGateway callGateway;
    @Autowired
    private RedisCache redisCache;
    @Value("${melhat.telemetry.stale-after-seconds:180}")
    private int staleAfterSeconds;

    @Transactional(rollbackFor = Exception.class)
    public CallDto start(String deviceIdRaw, String eventIdRaw, String kind, Boolean videoWanted, String idemKey)
    {
        siteAccessService.assertCanStartCall();
        CallDto replayed = replay("call.start", idemKey);
        if (replayed != null)
        {
            replayed.setCredentials(loadCredentials(Long.valueOf(replayed.getId()), true));
            return replayed;
        }
        WearSafetyEvent event = null;
        if (StringUtils.isNotEmpty(eventIdRaw))
        {
            event = eventMapper.selectById(Long.valueOf(eventIdRaw));
            if (event == null)
            {
                throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
            }
            siteAccessService.assertAuthorized(event.getSiteId());
        }
        Long deviceId;
        if (StringUtils.isNotEmpty(deviceIdRaw))
        {
            deviceId = Long.valueOf(deviceIdRaw);
        }
        else if (event != null && event.getDeviceId() != null)
        {
            deviceId = event.getDeviceId();
        }
        else
        {
            throw new ServiceException("设备不能为空", HttpStatus.BAD_REQUEST);
        }
        WearDevice device = deviceMapper.selectById(deviceId);
        siteAccessService.assertDeviceReadable(device);
        if (device.getSiteId() == null)
        {
            throw new ServiceException("请选择厂站", HttpStatus.BAD_REQUEST);
        }
        WearProductModel model = device.getModelId() == null ? null : modelMapper.selectById(device.getModelId());
        String caps = model == null ? null : model.getCapabilities();
        if (!DeviceCapability.supports(caps, "intercom"))
        {
            throw new ServiceException("该设备不支持通话", HttpStatus.CONFLICT);
        }
        boolean video = Boolean.TRUE.equals(videoWanted) && DeviceCapability.supports(caps, "video");
        if (StringUtils.isEmpty(kind))
        {
            kind = event != null && "sos".equals(event.getEventType()) ? "sos" : "single";
        }
        LoginUser user = siteAccessService.requireLogin();
        Date now = new Date();
        WearCallSession row = new WearCallSession();
        row.setKind(kind);
        row.setEventId(event == null ? null : event.getId());
        row.setDeviceId(device.getId());
        row.setSn(device.getSn());
        WearAssignment asg = assignmentMapper.findAtDeviceTime(device.getId(), now);
        row.setPersonId(asg == null ? (event == null ? null : event.getPersonId()) : asg.getPersonId());
        row.setSiteId(device.getSiteId());
        row.setRequesterUserId(user.getUserId());
        row.setStatus(CallStateMachine.REQUESTING);
        row.setVideo(video ? 1 : 0);
        row.setDemo(callGateway.isDemoMode() ? 1 : 0);
        row.setStartedAt(now);
        row.setVersion(1);
        row.setCreateBy(SecurityUtils.getUsername());
        row.setCreateTime(now);
        row.setUpdateTime(now);
        callMapper.insert(row);
        try
        {
            CallCredentialsDto cred = callGateway.issue(row.getId(), user.getUserId(), device.getSn(), video);
            row.setStatus(CallStateMachine.OFFERED);
            row.setChannelName(cred.getChannelName());
            row.setAgoraUid(cred.getAgoraUid());
            row.setExpiresAt(cred.getExpiresAt());
            row.setDemo(Boolean.TRUE.equals(cred.getDemo()) ? 1 : 0);
            row.setUpdateTime(new Date());
            callMapper.updateById(row);
            storeCredentials(row.getId(), cred);
            remember("call.start", idemKey, row.getId());
            CallDto dto = toDto(row, device);
            dto.setCredentials(cred);
            return dto;
        }
        catch (RuntimeException ex)
        {
            row.setStatus(CallStateMachine.FAILED);
            row.setFailReason("厂商不可达，通话未建立");
            row.setUpdateTime(new Date());
            callMapper.updateById(row);
            throw new ServiceException("厂商不可达，通话未建立", HttpStatus.CONFLICT);
        }
    }

    public CallDto detail(Long id)
    {
        return toDto(requireReadable(id), null);
    }

    public CallCredentialsDto credentials(Long id)
    {
        WearCallSession row = requireReadable(id);
        LoginUser user = siteAccessService.requireLogin();
        if (!user.getUserId().equals(row.getRequesterUserId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        CallCredentialsDto cred = loadCredentials(id, true);
        if (cred == null)
        {
            throw new ServiceException("凭证已过期，请刷新后重试", HttpStatus.CONFLICT);
        }
        return cred;
    }

    @Transactional(rollbackFor = Exception.class)
    public CallDto joined(Long id, String agoraUid)
    {
        siteAccessService.assertCanStartCall();
        WearCallSession row = requireReadable(id);
        LoginUser user = siteAccessService.requireLogin();
        if (!user.getUserId().equals(row.getRequesterUserId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        row = expireIfNeeded(row);
        if (!CallStateMachine.canJoin(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (StringUtils.isNotEmpty(row.getAgoraUid()) && StringUtils.isNotEmpty(agoraUid)
                && !row.getAgoraUid().equals(agoraUid.trim()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        Date now = new Date();
        row.setStatus(CallStateMachine.CONNECTED);
        row.setConnectedAt(now);
        row.setUpdateTime(now);
        row.setVersion(row.getVersion() == null ? 1 : row.getVersion() + 1);
        callMapper.updateById(row);
        return toDto(row, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public CallDto end(Long id)
    {
        siteAccessService.assertCanStartCall();
        WearCallSession row = requireReadable(id);
        LoginUser user = siteAccessService.requireLogin();
        if (!user.getUserId().equals(row.getRequesterUserId()) && !siteAccessService.canStartCall())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        if (CallStateMachine.ENDED.equals(row.getStatus()))
        {
            return toDto(row, null);
        }
        Date now = new Date();
        row.setStatus(CallStateMachine.ENDED);
        row.setEndedAt(now);
        row.setUpdateTime(now);
        row.setVersion(row.getVersion() == null ? 1 : row.getVersion() + 1);
        callMapper.updateById(row);
        callGateway.endChannel(row.getChannelName());
        callGateway.endDevice(row.getSn());
        return toDto(row, null);
    }

    public List<CallDto> forEvent(Long eventId)
    {
        WearSafetyEvent event = eventMapper.selectById(eventId);
        if (event == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(event.getSiteId());
        List<WearCallSession> rows = callMapper.selectList(new LambdaQueryWrapper<WearCallSession>()
                .eq(WearCallSession::getEventId, eventId).orderByDesc(WearCallSession::getId));
        return mapList(rows);
    }

    public List<CallDto> forDevice(Long deviceId)
    {
        WearDevice device = deviceMapper.selectById(deviceId);
        siteAccessService.assertDeviceReadable(device);
        List<WearCallSession> rows = callMapper.selectList(new LambdaQueryWrapper<WearCallSession>()
                .eq(WearCallSession::getDeviceId, deviceId).orderByDesc(WearCallSession::getId).last("LIMIT 20"));
        return mapList(rows);
    }

    private List<CallDto> mapList(List<WearCallSession> rows)
    {
        List<CallDto> list = new ArrayList<CallDto>();
        for (WearCallSession row : rows)
        {
            list.add(toDto(expireIfNeeded(row), null));
        }
        return list;
    }

    private WearCallSession requireReadable(Long id)
    {
        WearCallSession row = callMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(row.getSiteId());
        return expireIfNeeded(row);
    }

    private WearCallSession expireIfNeeded(WearCallSession row)
    {
        if (row == null || !CallStateMachine.OFFERED.equals(row.getStatus()) || row.getStartedAt() == null)
        {
            return row;
        }
        if (System.currentTimeMillis() - row.getStartedAt().getTime() <= 60_000L)
        {
            return row;
        }
        row.setStatus(CallStateMachine.TIMED_OUT);
        row.setUpdateTime(new Date());
        callMapper.updateById(row);
        return row;
    }

    private void storeCredentials(Long callId, CallCredentialsDto cred)
    {
        int ttl = 3600;
        if (cred.getExpiresAt() != null)
        {
            long sec = (cred.getExpiresAt().getTime() - System.currentTimeMillis()) / 1000L;
            if (sec > 10 && sec < 86400)
            {
                ttl = (int) sec;
            }
        }
        redisCache.setCacheObject("wear:call:cred:" + callId, JSON.toJSONString(cred), ttl, TimeUnit.SECONDS);
    }

    private CallCredentialsDto loadCredentials(Long callId, boolean includeToken)
    {
        Object raw = redisCache.getCacheObject("wear:call:cred:" + callId);
        if (raw == null)
        {
            return null;
        }
        CallCredentialsDto cred = JSON.parseObject(String.valueOf(raw), CallCredentialsDto.class);
        if (!includeToken && cred != null)
        {
            cred.setAgoraToken(null);
        }
        return cred;
    }

    private CallDto replay(String scope, String idemKey)
    {
        if (StringUtils.isEmpty(idemKey))
        {
            return null;
        }
        WearIdempotency row = idempotencyMapper.selectOne(new LambdaQueryWrapper<WearIdempotency>()
                .eq(WearIdempotency::getScope, scope).eq(WearIdempotency::getIdemKey, idemKey.trim()).last("LIMIT 1"));
        if (row == null)
        {
            return null;
        }
        WearCallSession session = callMapper.selectById(row.getResourceId());
        return session == null ? null : toDto(session, null);
    }

    private void remember(String scope, String idemKey, Long resourceId)
    {
        if (StringUtils.isEmpty(idemKey))
        {
            return;
        }
        WearIdempotency row = new WearIdempotency();
        row.setScope(scope);
        row.setIdemKey(idemKey.trim());
        row.setResourceId(resourceId);
        row.setCreateTime(new Date());
        try
        {
            idempotencyMapper.insert(row);
        }
        catch (DataIntegrityViolationException ignored)
        {
        }
    }

    private CallDto toDto(WearCallSession row, WearDevice device)
    {
        CallDto dto = new CallDto();
        dto.setId(String.valueOf(row.getId()));
        dto.setKind(row.getKind());
        dto.setStatus(row.getStatus());
        dto.setEventId(row.getEventId() == null ? null : String.valueOf(row.getEventId()));
        dto.setDeviceId(String.valueOf(row.getDeviceId()));
        dto.setSn(row.getSn());
        dto.setPersonId(row.getPersonId() == null ? null : String.valueOf(row.getPersonId()));
        dto.setSiteId(String.valueOf(row.getSiteId()));
        dto.setRequesterUserId(String.valueOf(row.getRequesterUserId()));
        dto.setChannelName(row.getChannelName());
        dto.setVideo(row.getVideo() != null && row.getVideo().intValue() == 1);
        dto.setDemo(row.getDemo() != null && row.getDemo().intValue() == 1);
        dto.setExpiresAt(row.getExpiresAt());
        dto.setStartedAt(row.getStartedAt());
        dto.setConnectedAt(row.getConnectedAt());
        dto.setEndedAt(row.getEndedAt());
        dto.setFailReason(row.getFailReason());
        dto.setVersion(row.getVersion());
        WearDevice d = device != null ? device : deviceMapper.selectById(row.getDeviceId());
        Date last = d == null ? null : d.getLastReportedAt();
        dto.setConnectionQuality(TelemetryFreshness.connectionQuality(last, new Date(), staleAfterSeconds));
        return dto;
    }
}
