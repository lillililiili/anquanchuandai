package com.ruoyi.portal;
import org.springframework.web.bind.annotation.*;
import org.springframework.util.MultiValueMap;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalS2Models.*;
@RestController @RequestMapping("/api/portal/v1")
public class PortalS2Controller {
    private final PortalS2Service service;
    public PortalS2Controller(PortalS2Service s){service=s;}
    private <T> Envelope<T> ok(T data){return new Envelope<>(200,"成功",null,data);}
    @GetMapping("/devices") public Envelope<Page<DeviceOption>> devices(@RequestParam MultiValueMap<String,String> p){return ok(service.devices(PortalS2Query.parse(p,"devices")));}
    @GetMapping("/locations/latest") public Envelope<Page<LocatedDevice>> locations(@RequestParam MultiValueMap<String,String> p){return ok(service.locations(PortalS2Query.parse(p,"locations")));}
    @GetMapping("/tracks") public Envelope<Section<Track>> tracks(@RequestParam MultiValueMap<String,String> p){return ok(service.tracks(PortalS2Query.parse(p,"tracks")));}
    @GetMapping("/fences") public Envelope<Page<Fence>> fences(@RequestParam MultiValueMap<String,String> p){return ok(service.fences(PortalS2Query.parse(p,"fences")));}
    @GetMapping("/fences/{id}") public Envelope<Fence> fence(@PathVariable String id,@RequestParam MultiValueMap<String,String> p){return ok(service.fence(PortalS2Query.parse(p,"detail"),id));}
    @GetMapping("/materials") public Envelope<Page<Material>> materials(@RequestParam MultiValueMap<String,String> p){return ok(service.materials(PortalS2Query.parse(p,"materials")));}
    @GetMapping("/materials/{id}") public Envelope<Material> material(@PathVariable String id,@RequestParam MultiValueMap<String,String> p){return ok(service.material(PortalS2Query.parse(p,"detail"),id));}
}
