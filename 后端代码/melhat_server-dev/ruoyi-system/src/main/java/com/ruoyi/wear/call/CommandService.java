package com.ruoyi.wear.call;

import java.util.ArrayList;
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
import com.ruoyi.wear.assignment.domain.WearIdempotency;
import com.ruoyi.wear.assignment.mapper.WearIdempotencyMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.call.domain.WearDeviceCommand;
import com.ruoyi.wear.call.dto.CommandDto;
import com.ruoyi.wear.call.mapper.WearDeviceCommandMapper;
import com.ruoyi.wear.device.DeviceCapability;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;

@Service
public class CommandService
{
    @Autowired
    private WearDeviceCommandMapper commandMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private CallGateway callGateway;
    @Autowired
    private WearIdempotencyMapper idempotencyMapper;

    @Transactional(rollbackFor = Exception.class)
    public List<CommandDto> tts(List<String> deviceIds, String text, String eventId, String idemKey)
    {
        siteAccessService.assertCanSendTts();
        if (StringUtils.isEmpty(text))
        {
            throw new ServiceException("播报内容不能为空", HttpStatus.BAD_REQUEST);
        }
        if (deviceIds == null || deviceIds.isEmpty())
        {
            throw new ServiceException("设备不能为空", HttpStatus.BAD_REQUEST);
        }
        if (StringUtils.isNotEmpty(idemKey) && deviceIds.size() == 1)
        {
            CommandDto replayed = replay("command.tts", idemKey);
            if (replayed != null)
            {
                List<CommandDto> one = new ArrayList<CommandDto>();
                one.add(replayed);
                return one;
            }
        }
        List<CommandDto> result = new ArrayList<CommandDto>();
        int index = 0;
        for (String rawId : deviceIds)
        {
            Long deviceId = Long.valueOf(rawId);
            WearDevice device = deviceMapper.selectById(deviceId);
            siteAccessService.assertDeviceReadable(device);
            WearProductModel model = device.getModelId() == null ? null : modelMapper.selectById(device.getModelId());
            if (!DeviceCapability.supports(model == null ? null : model.getCapabilities(), "tts"))
            {
                throw new ServiceException("该设备不支持播报", HttpStatus.CONFLICT);
            }
            Date now = new Date();
            WearDeviceCommand row = new WearDeviceCommand();
            row.setKind("tts");
            row.setDeviceId(device.getId());
            row.setSn(device.getSn());
            row.setEventId(StringUtils.isEmpty(eventId) ? null : Long.valueOf(eventId));
            row.setPayload(text);
            row.setStatus("accepted");
            row.setCreateBy(SecurityUtils.getUsername());
            row.setCreateTime(now);
            if (!callGateway.isDemoMode())
            {
                try
                {
                    boolean sent = callGateway.sendTts(device.getSn(), text);
                    row.setStatus(sent ? "sent" : "unknown");
                }
                catch (RuntimeException ex)
                {
                    row.setStatus("failed");
                    row.setVendorMsg("厂商不可达");
                }
            }
            commandMapper.insert(row);
            if (index == 0)
            {
                remember("command.tts", idemKey, row.getId());
            }
            result.add(toDto(row));
            index++;
        }
        return result;
    }

    public CommandDto detail(Long id)
    {
        WearDeviceCommand row = commandMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        WearDevice device = deviceMapper.selectById(row.getDeviceId());
        siteAccessService.assertDeviceReadable(device);
        return toDto(row);
    }

    private CommandDto replay(String scope, String idemKey)
    {
        WearIdempotency row = idempotencyMapper.selectOne(new LambdaQueryWrapper<WearIdempotency>()
                .eq(WearIdempotency::getScope, scope).eq(WearIdempotency::getIdemKey, idemKey.trim()).last("LIMIT 1"));
        if (row == null)
        {
            return null;
        }
        WearDeviceCommand cmd = commandMapper.selectById(row.getResourceId());
        return cmd == null ? null : toDto(cmd);
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

    private CommandDto toDto(WearDeviceCommand row)
    {
        CommandDto dto = new CommandDto();
        dto.setId(String.valueOf(row.getId()));
        dto.setKind(row.getKind());
        dto.setDeviceId(String.valueOf(row.getDeviceId()));
        dto.setSn(row.getSn());
        dto.setEventId(row.getEventId() == null ? null : String.valueOf(row.getEventId()));
        dto.setPayload(row.getPayload());
        dto.setStatus(row.getStatus());
        dto.setVendorMsg(row.getVendorMsg());
        dto.setHeard(Boolean.FALSE);
        dto.setCreateTime(row.getCreateTime());
        return dto;
    }
}
