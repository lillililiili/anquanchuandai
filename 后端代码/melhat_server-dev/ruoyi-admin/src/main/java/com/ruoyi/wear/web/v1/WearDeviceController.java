package com.ruoyi.wear.web.v1;

import java.util.List;
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
import com.ruoyi.wear.device.DeviceService;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.dto.DeviceWriteRequest;
import com.ruoyi.wear.helmet.HelmetQueryService;

@RestController
@RequestMapping("/api/v1/devices")
public class WearDeviceController
{
    @Autowired
    private DeviceService deviceService;
    @Autowired
    private HelmetQueryService helmetQueryService;

    @GetMapping
    public R<WearPage<DeviceDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String typeCode,
            @RequestParam(required = false) String modelId,
            @RequestParam(required = false) String sn,
            @RequestParam(required = false) String assetStatus)
    {
        return R.ok(deviceService.page(current, size, typeCode, modelId, sn, assetStatus));
    }

    @GetMapping("/legacy-preview")
    public R<List<Map<String, String>>> legacyPreview()
    {
        return R.ok(deviceService.legacyPreview());
    }

    @GetMapping("/{id}")
    public R<DeviceDto> detail(@PathVariable Long id)
    {
        return R.ok(deviceService.detail(id));
    }

    @GetMapping("/{id}/samples")
    public R<List<Map<String, Object>>> samples(@PathVariable Long id)
    {
        return R.ok(helmetQueryService.samples(id));
    }

    @GetMapping("/{id}/ingest")
    public R<List<Map<String, Object>>> ingest(@PathVariable Long id)
    {
        return R.ok(helmetQueryService.ingest(id));
    }

    @PostMapping
    public R<DeviceDto> create(@RequestBody DeviceWriteRequest request)
    {
        return R.ok(deviceService.create(request));
    }

    @PutMapping("/{id}")
    public R<DeviceDto> update(@PathVariable Long id, @RequestBody DeviceWriteRequest request)
    {
        return R.ok(deviceService.update(id, request));
    }

    @PutMapping("/{id}/site")
    public R<DeviceDto> assignSite(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        String siteId = body.get("siteId") == null ? null : String.valueOf(body.get("siteId"));
        if (siteId != null && ("null".equals(siteId) || siteId.trim().isEmpty()))
        {
            siteId = null;
        }
        Integer version = body.get("version") == null ? null : Integer.valueOf(String.valueOf(body.get("version")));
        return R.ok(deviceService.assignSite(id, siteId, version));
    }

    @PutMapping("/{id}/asset-status")
    public R<DeviceDto> changeAssetStatus(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        String status = body.get("assetStatus") == null ? null : String.valueOf(body.get("assetStatus"));
        Integer version = body.get("version") == null ? null : Integer.valueOf(String.valueOf(body.get("version")));
        return R.ok(deviceService.changeAssetStatus(id, status, version));
    }
}
