package com.ruoyi.portal;
import org.springframework.web.bind.annotation.*;
import org.springframework.util.MultiValueMap;
import com.ruoyi.portal.PortalModels.*;
@RestController
@RequestMapping("/api/portal/v1")
public class PortalController {
    private final PortalService service;
    public PortalController(PortalService service) { this.service=service; }
    private <T> Envelope<T> ok(T value) { return new Envelope<>(200,"成功",null,value); }
    @GetMapping("/context")
    public Envelope<Context> context(@RequestParam MultiValueMap<String,String> params) {
        PortalQuery.parse(params,"context");return ok(service.context());
    }
    @GetMapping("/people")
    public Envelope<Page<Person>> people(@RequestParam MultiValueMap<String,String> params) {
        return ok(service.people(PortalQuery.parse(params,"people")));
    }
    @GetMapping("/people/{personId}")
    public Envelope<Detail> detail(@PathVariable String personId,@RequestParam MultiValueMap<String,String> params) {
        return ok(service.detail(PortalQuery.parse(params,"detail"),personId));
    }
    @GetMapping("/people/{personId}/equipment-history")
    public Envelope<Page<History>> history(@PathVariable String personId,@RequestParam MultiValueMap<String,String> params) {
        return ok(service.history(PortalQuery.parse(params,"history"),personId));
    }
}

