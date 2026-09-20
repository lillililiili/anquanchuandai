package com.ruoyi.portal;
import org.springframework.web.bind.annotation.*;
import org.springframework.util.MultiValueMap;
import com.ruoyi.portal.PortalModels.Envelope;
import com.ruoyi.portal.PortalModels.Page;
import com.ruoyi.portal.PortalModels.Section;
import com.ruoyi.portal.PortalEventModels.*;
@RestController @RequestMapping("/api/portal/v1/events")
public class PortalEventController {
    private final PortalEventService service; public PortalEventController(PortalEventService s){service=s;}
    private <T>Envelope<T> ok(T d){return new Envelope<>(200,"成功",null,d);}
    @GetMapping public Envelope<EventPage> list(@RequestParam MultiValueMap<String,String>p){return ok(service.list(PortalEventQuery.parse(p,"list")));}
    @GetMapping("/summary") public Envelope<Section<Statistics>> summary(@RequestParam MultiValueMap<String,String>p){return ok(service.summary(PortalEventQuery.parse(p,"summary")));}
    @GetMapping("/{eventId}") public Envelope<Detail> detail(@PathVariable String eventId,@RequestParam MultiValueMap<String,String>p){return ok(service.detail(PortalEventQuery.parse(p,"detail"),eventId));}
    @GetMapping("/{eventId}/timeline") public Envelope<Page<Timeline>> timeline(@PathVariable String eventId,@RequestParam MultiValueMap<String,String>p){return ok(service.timeline(PortalEventQuery.parse(p,"records"),eventId));}
    @GetMapping("/{eventId}/verifications") public Envelope<Page<Verification>> verifications(@PathVariable String eventId,@RequestParam MultiValueMap<String,String>p){return ok(service.verifications(PortalEventQuery.parse(p,"records"),eventId));}
}
