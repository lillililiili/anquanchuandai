package com.ruoyi.wear.web.v1;

import java.util.ArrayList;
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
import com.ruoyi.wear.call.CommandService;
import com.ruoyi.wear.call.dto.CommandDto;

@RestController
@RequestMapping("/api/v1/commands")
public class WearCommandController
{
    @Autowired
    private CommandService commandService;

    @PostMapping("/tts")
    public R<List<CommandDto>> tts(@RequestBody Map<String, Object> body)
    {
        List<String> ids = new ArrayList<String>();
        Object raw = body == null ? null : body.get("deviceIds");
        if (raw instanceof List)
        {
            for (Object item : (List<?>) raw)
            {
                if (item != null)
                {
                    ids.add(String.valueOf(item));
                }
            }
        }
        String text = body == null || body.get("text") == null ? null : String.valueOf(body.get("text"));
        String eventId = body == null || body.get("eventId") == null ? null : String.valueOf(body.get("eventId"));
        String idem = body == null || body.get("idempotencyKey") == null ? null : String.valueOf(body.get("idempotencyKey"));
        return R.ok(commandService.tts(ids, text, eventId, idem));
    }

    @GetMapping("/{id:\\d+}")
    public R<CommandDto> detail(@PathVariable Long id)
    {
        return R.ok(commandService.detail(id));
    }
}
