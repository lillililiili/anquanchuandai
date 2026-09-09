package com.ruoyi.wear.web.v1;

import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
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
import com.ruoyi.wear.location.FenceService;
import com.ruoyi.wear.location.dto.GeoFenceDto;

@RestController
@RequestMapping("/api/v1/fences")
public class WearFenceController
{
    @Autowired
    private FenceService fenceService;

    @GetMapping
    public R<WearPage<GeoFenceDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size)
    {
        return R.ok(fenceService.page(current, size));
    }

    @PostMapping
    public R<GeoFenceDto> create(@RequestBody Map<String, Object> body)
    {
        return R.ok(fenceService.create(body));
    }

    @GetMapping("/{id:\\d+}")
    public R<GeoFenceDto> detail(@PathVariable Long id)
    {
        return R.ok(fenceService.detail(id));
    }

    @PutMapping("/{id:\\d+}")
    public R<GeoFenceDto> update(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(fenceService.update(id, body));
    }

    @PutMapping("/{id:\\d+}/enabled")
    public R<GeoFenceDto> enabled(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(fenceService.setEnabled(id, body));
    }

    @PostMapping("/evaluate")
    public R<Map<String, Object>> evaluate(@RequestBody Map<String, Object> body)
    {
        return R.ok(fenceService.evaluate(body));
    }
}
