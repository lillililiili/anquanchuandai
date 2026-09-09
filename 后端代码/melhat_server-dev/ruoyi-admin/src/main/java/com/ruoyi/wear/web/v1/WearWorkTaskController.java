package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.work.WorkTaskService;
import com.ruoyi.wear.work.dto.EquipmentCheckDto;
import com.ruoyi.wear.work.dto.WorkTaskDto;

@RestController
@RequestMapping("/api/v1/work-tasks")
public class WearWorkTaskController
{
    @Autowired
    private WorkTaskService workTaskService;

    @GetMapping
    public R<WearPage<WorkTaskDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String workType)
    {
        return R.ok(workTaskService.page(current, size, status, workType));
    }

    @GetMapping("/mine")
    public R<WearPage<WorkTaskDto>> mine(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size)
    {
        return R.ok(workTaskService.mine(current, size));
    }

    @PostMapping
    public R<WorkTaskDto> create(@RequestBody Map<String, Object> body)
    {
        return R.ok(workTaskService.create(body));
    }

    @GetMapping("/{id:\\d+}")
    public R<WorkTaskDto> detail(@PathVariable Long id)
    {
        return R.ok(workTaskService.detail(id));
    }

    @PutMapping("/{id:\\d+}")
    public R<WorkTaskDto> update(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(workTaskService.update(id, body));
    }

    @PostMapping("/{id:\\d+}/members")
    public R<WorkTaskDto> addMembers(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(workTaskService.addMembers(id, body));
    }

    @DeleteMapping("/{id:\\d+}/members/{personId:\\d+}")
    public R<WorkTaskDto> removeMember(@PathVariable Long id, @PathVariable Long personId)
    {
        return R.ok(workTaskService.removeMember(id, personId));
    }

    @PostMapping("/{id:\\d+}/start")
    public R<WorkTaskDto> start(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        return R.ok(workTaskService.start(id, intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/pause")
    public R<WorkTaskDto> pause(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        return R.ok(workTaskService.pause(id, intVal(body, "version")));
    }

    @PostMapping("/{id:\\d+}/end")
    public R<WorkTaskDto> end(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        boolean ack = body != null && (Boolean.TRUE.equals(body.get("acknowledgeOpenHighRisk"))
                || "true".equalsIgnoreCase(String.valueOf(body.get("acknowledgeOpenHighRisk"))));
        return R.ok(workTaskService.end(id, intVal(body, "version"), ack));
    }

    @GetMapping("/{id:\\d+}/equipment-check")
    public R<List<EquipmentCheckDto>> equipment(@PathVariable Long id)
    {
        return R.ok(workTaskService.equipmentCheck(id));
    }

    @GetMapping("/{id:\\d+}/events")
    public R<List<EventDto>> events(@PathVariable Long id)
    {
        return R.ok(workTaskService.events(id));
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
}
