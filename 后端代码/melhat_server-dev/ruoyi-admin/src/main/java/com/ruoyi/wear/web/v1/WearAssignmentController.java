package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import javax.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.assignment.AssignmentService;
import com.ruoyi.wear.assignment.dto.AssignmentDto;
import com.ruoyi.wear.assignment.dto.IssueRequest;

@RestController
@RequestMapping("/api/v1")
public class WearAssignmentController
{
    @Autowired
    private AssignmentService assignmentService;

    @PostMapping("/assignments")
    public R<AssignmentDto> issue(@RequestBody IssueRequest request, HttpServletRequest http)
    {
        return R.ok(assignmentService.issue(request, http.getHeader("Idempotency-Key")));
    }

    @PostMapping("/assignments/{id}/return")
    public R<AssignmentDto> giveBack(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body,
            HttpServletRequest http)
    {
        String reason = body == null || body.get("reason") == null ? null : String.valueOf(body.get("reason"));
        String key = body == null || body.get("idempotencyKey") == null ? null : String.valueOf(body.get("idempotencyKey"));
        if (key == null)
        {
            key = http.getHeader("Idempotency-Key");
        }
        return R.ok(assignmentService.giveBack(id, reason, key));
    }

    @PostMapping("/assignments/{id}/recover")
    public R<AssignmentDto> recover(@PathVariable Long id, @RequestBody Map<String, Object> body,
            HttpServletRequest http)
    {
        String reason = body.get("reason") == null ? null : String.valueOf(body.get("reason"));
        String status = body.get("assetStatus") == null ? null : String.valueOf(body.get("assetStatus"));
        String key = body.get("idempotencyKey") == null ? http.getHeader("Idempotency-Key") : String.valueOf(body.get("idempotencyKey"));
        return R.ok(assignmentService.recover(id, reason, status, key));
    }

    @GetMapping("/assignments/{id}")
    public R<AssignmentDto> detail(@PathVariable Long id)
    {
        return R.ok(assignmentService.detail(id));
    }

    @GetMapping("/devices/{id}/assignment")
    public R<AssignmentDto> currentDevice(@PathVariable Long id)
    {
        return R.ok(assignmentService.currentForDevice(id));
    }

    @GetMapping("/devices/{id}/assignments")
    public R<List<AssignmentDto>> deviceHistory(@PathVariable Long id)
    {
        return R.ok(assignmentService.historyForDevice(id));
    }

    @GetMapping("/people/{id}/equipment")
    public R<List<AssignmentDto>> personEquipment(@PathVariable Long id)
    {
        return R.ok(assignmentService.equipmentForPerson(id));
    }

    @GetMapping("/people/{id}/assignments")
    public R<List<AssignmentDto>> personHistory(@PathVariable Long id)
    {
        return R.ok(assignmentService.historyForPerson(id));
    }

    @GetMapping("/me/equipment")
    public R<List<AssignmentDto>> myEquipment()
    {
        return R.ok(assignmentService.myEquipment());
    }
}
