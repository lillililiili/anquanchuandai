package com.ruoyi.wear.web.v1;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.location.LocationQueryService;
import com.ruoyi.wear.location.dto.PersonLocationDto;
import com.ruoyi.wear.location.dto.TrackPointDto;

@RestController
@RequestMapping("/api/v1/locations/people")
public class WearLocationController
{
    @Autowired
    private LocationQueryService locationQueryService;

    @GetMapping
    public R<WearPage<PersonLocationDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size)
    {
        return R.ok(locationQueryService.page(current, size));
    }

    @GetMapping("/{id:\\d+}")
    public R<PersonLocationDto> detail(@PathVariable Long id)
    {
        return R.ok(locationQueryService.detail(id));
    }

    @GetMapping("/{id:\\d+}/tracks")
    public R<WearPage<TrackPointDto>> tracks(
            @PathVariable Long id,
            @RequestParam String from,
            @RequestParam String to,
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "50") int size)
    {
        return R.ok(locationQueryService.tracks(id, from, to, current, size));
    }
}
