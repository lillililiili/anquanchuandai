package com.ruoyi.portal;
import org.springframework.web.bind.annotation.*;
import org.springframework.util.MultiValueMap;
import com.ruoyi.portal.PortalModels.Envelope;
import com.ruoyi.portal.PortalVideoModels.*;
@RestController @RequestMapping("/api/portal/v1/video-sources")
public class PortalVideoController {
    private final PortalVideoService service;
    public PortalVideoController(PortalVideoService s){service=s;}
    @GetMapping public Envelope<VideoPage> list(@RequestParam MultiValueMap<String,String> p){return new Envelope<>(200,"成功",null,service.list(PortalVideoQuery.parse(p,false)));}
    @GetMapping("/{deviceId}") public Envelope<Detail> detail(@PathVariable String deviceId,@RequestParam MultiValueMap<String,String> p){return new Envelope<>(200,"成功",null,service.detail(PortalVideoQuery.parse(p,true),deviceId));}
}
