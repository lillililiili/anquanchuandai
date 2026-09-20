package com.ruoyi.wear.web.v1;

import java.util.Map;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.wear.calllab.WearCallLabBridgeService;

/** Explicit business entrypoints: never a general-purpose HTTP proxy. */
@RestController
@RequestMapping("/api/v1/lab")
@Profile("!prod")
@ConditionalOnProperty(prefix = "melhat.call-lab", name = "enabled", havingValue = "true", matchIfMissing = false)
public class WearCallLabBridgeController
{
    @Autowired
    private WearCallLabBridgeService bridge;

    @GetMapping("/bridge-info")
    public ResponseEntity<byte[]> info(HttpServletRequest request) { return bridge.info(request); }

    @GetMapping("/roster")
    public ResponseEntity<byte[]> roster(HttpServletRequest request) { return bridge.forward(request, "GET", "/roster", null); }

    @GetMapping("/state")
    public ResponseEntity<byte[]> state(HttpServletRequest request) { return bridge.forward(request, "GET", "/state", null); }

    @GetMapping("/calls/{id}/video/stream")
    public void videoStream(HttpServletRequest request, HttpServletResponse response, @PathVariable String id)
            throws java.io.IOException
    { bridge.videoStream(request, response, id); }

    @PostMapping("/presence")
    public ResponseEntity<byte[]> presence(HttpServletRequest request, @RequestBody Map<String, Object> body)
    { return bridge.forward(request, "POST", "/presence", body); }

    @PostMapping("/calls")
    public ResponseEntity<byte[]> call(HttpServletRequest request, @RequestBody Map<String, Object> body)
    { return bridge.forward(request, "POST", "/calls", body); }

    @PostMapping("/calls/{id}/{action:accept|reject|end|video|invite}")
    public ResponseEntity<byte[]> action(HttpServletRequest request, @PathVariable String id,
            @PathVariable String action, @RequestBody(required = false) Map<String, Object> body)
    { return bridge.forward(request, "POST", "/calls/" + id + "/" + action, body); }

    @PostMapping("/tts")
    public ResponseEntity<byte[]> tts(HttpServletRequest request, @RequestBody Map<String, Object> body)
    { return bridge.forward(request, "POST", "/tts", body); }

    @PostMapping("/tts/ack")
    public ResponseEntity<byte[]> acknowledge(HttpServletRequest request, @RequestBody Map<String, Object> body)
    { return bridge.forward(request, "POST", "/tts/ack", body); }
}
