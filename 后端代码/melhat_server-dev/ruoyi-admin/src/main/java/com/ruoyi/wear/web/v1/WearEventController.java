package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.event.EventCommandService;
import com.ruoyi.wear.event.EventQueryService;
import com.ruoyi.wear.event.dto.EventActionDto;
import com.ruoyi.wear.event.dto.EventDto;

@RestController
@RequestMapping("/api/v1/events")
public class WearEventController
{
    @Autowired
    private EventQueryService queryService;
    @Autowired
    private EventCommandService commandService;

    @GetMapping
    public R<WearPage<EventDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String type,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String personId,
            @RequestParam(required = false) String severity,
            @RequestParam(required = false) String updatedAfter,
            @RequestParam(required = false) String claimantUserId,
            @RequestParam(required = false) String escalated)
    {
        return R.ok(queryService.page(current, size, type, status, personId, severity, updatedAfter, claimantUserId, escalated));
    }

    @GetMapping("/inbox/count")
    public R<Map<String, Object>> inboxCount()
    {
        return R.ok(queryService.inboxCount());
    }

    @GetMapping("/{id:\\d+}")
    public R<EventDto> detail(@PathVariable Long id)
    {
        return R.ok(queryService.detail(id));
    }

    @GetMapping("/{id:\\d+}/actions")
    public R<List<EventActionDto>> actions(@PathVariable Long id)
    {
        return R.ok(queryService.actions(id));
    }

    @PostMapping("/{id:\\d+}/ack")
    public R<EventDto> ack(@PathVariable Long id)
    {
        return R.ok(commandService.ack(id));
    }

    @PostMapping("/{id:\\d+}/claim")
    public R<EventDto> claim(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        return R.ok(commandService.claim(id, intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/handle")
    public R<EventDto> handle(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        return R.ok(commandService.handle(id, strVal(body, "comment"), intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/transfer")
    public R<EventDto> transfer(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(commandService.transfer(id, strVal(body, "toUserId"), strVal(body, "reason"), intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/close")
    public R<EventDto> close(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(commandService.close(id, strVal(body, "reason"), intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/reopen")
    public R<EventDto> reopen(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(commandService.reopen(id, strVal(body, "reason"), intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/task")
    public R<EventDto> assignTask(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(commandService.assignTask(id, strVal(body, "taskId"), intVal(body, "version")));
    }

    private Integer intVal(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null || String.valueOf(body.get(key)).trim().isEmpty())
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

    private String strVal(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return null;
        }
        return String.valueOf(body.get(key));
    }
}
