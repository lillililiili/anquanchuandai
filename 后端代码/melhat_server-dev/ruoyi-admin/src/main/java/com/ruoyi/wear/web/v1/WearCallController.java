package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.call.CallService;
import com.ruoyi.wear.call.dto.CallCredentialsDto;
import com.ruoyi.wear.call.dto.CallDto;

@RestController
@RequestMapping("/api/v1")
public class WearCallController
{
    @Autowired
    private CallService callService;

    @PostMapping("/calls")
    public R<CallDto> start(@RequestBody Map<String, Object> body)
    {
        Boolean video = body.get("video") == null ? Boolean.FALSE : Boolean.valueOf(String.valueOf(body.get("video")));
        return R.ok(callService.start(str(body, "deviceId"), str(body, "eventId"), str(body, "kind"),
                video, str(body, "idempotencyKey")));
    }

    @GetMapping("/calls/{id:\\d+}")
    public R<CallDto> detail(@PathVariable Long id)
    {
        return R.ok(callService.detail(id));
    }

    @GetMapping("/calls/{id:\\d+}/credentials")
    public R<CallCredentialsDto> credentials(@PathVariable Long id)
    {
        return R.ok(callService.credentials(id));
    }

    @PostMapping("/calls/{id:\\d+}/joined")
    public R<CallDto> joined(@PathVariable Long id, @RequestBody(required = false) Map<String, Object> body)
    {
        return R.ok(callService.joined(id, body == null ? null : str(body, "agoraUid")));
    }

    @PostMapping("/calls/{id:\\d+}/end")
    public R<CallDto> end(@PathVariable Long id)
    {
        return R.ok(callService.end(id));
    }

    @GetMapping("/events/{id:\\d+}/calls")
    public R<List<CallDto>> eventCalls(@PathVariable Long id)
    {
        return R.ok(callService.forEvent(id));
    }

    @GetMapping("/devices/{id:\\d+}/calls")
    public R<List<CallDto>> deviceCalls(@PathVariable Long id)
    {
        return R.ok(callService.forDevice(id));
    }

    private String str(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return null;
        }
        String value = String.valueOf(body.get(key));
        return "null".equals(value) ? null : value;
    }
}
