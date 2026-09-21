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
import com.ruoyi.wear.work.DutyService;
import com.ruoyi.wear.work.dto.HandoverDto;

@RestController
@RequestMapping("/api/v1/duty")
public class WearDutyController
{
    @Autowired
    private DutyService dutyService;
    @Autowired private com.ruoyi.wear.work.DutyLedgerService ledger;

    @GetMapping("/shifts")
    public R<Map<String,Object>> shifts(@RequestParam(defaultValue="1") int current, @RequestParam(defaultValue="20") int size)
    {
        return R.ok(ledger.page(current, size));
    }

    @PostMapping("/takeover")
    public R<HandoverDto> takeover(@RequestBody Map<String,Object> body)
    {
        return R.ok(dutyService.takeover(body));
    }

    @PostMapping("/handovers/{id:\\d+}/cancel")
    public R<HandoverDto> cancel(@PathVariable Long id, @RequestBody Map<String,Object> body)
    {
        return R.ok(dutyService.cancel(id, body));
    }

    @GetMapping("/summary")
    public R<Map<String, Object>> summary()
    {
        return R.ok(dutyService.summary());
    }

    @GetMapping("/operators")
    public R<List<Map<String, String>>> operators()
    {
        return R.ok(dutyService.operators());
    }

    @GetMapping("/handovers")
    public R<List<HandoverDto>> handovers()
    {
        return R.ok(dutyService.handovers());
    }

    @PostMapping("/handovers")
    public R<HandoverDto> create(@RequestBody Map<String, Object> body)
    {
        return R.ok(dutyService.createHandover(body));
    }

    @PostMapping("/handovers/{id:\\d+}/confirm")
    public R<HandoverDto> confirm(@PathVariable Long id)
    {
        return R.ok(dutyService.confirm(id));
    }
}
