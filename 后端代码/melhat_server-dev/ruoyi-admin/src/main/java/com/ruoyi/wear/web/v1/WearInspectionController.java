package com.ruoyi.wear.web.v1;

import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.work.InspectionService;

@RestController
@RequestMapping("/api/v1/work-tasks/{taskId:\\d+}/inspection")
public class WearInspectionController {
    @Autowired private InspectionService service;
    @GetMapping public R<Map<String,Object>> summary(@PathVariable Long taskId) { return R.ok(service.summary(taskId)); }
    @PostMapping("/select") public R<Map<String,Object>> select(@PathVariable Long taskId,@RequestBody Map<String,Object> body) {
        return R.ok(service.select(taskId,itemId(body)));
    }
    @PostMapping("/records") public R<Map<String,Object>> record(@PathVariable Long taskId,@RequestBody Map<String,Object> body) {
        return R.ok(service.record(taskId,itemId(body),Objects.toString(body.get("requestId"),"")));
    }
    @PostMapping("/items") public R<Map<String,Object>> add(@PathVariable Long taskId,@RequestBody Map<String,Object> body) {
        return R.ok(service.addItem(taskId,body));
    }
    @PostMapping(value="/reports",consumes=MediaType.MULTIPART_FORM_DATA_VALUE)
    public R<Map<String,Object>> report(@PathVariable Long taskId,@RequestParam Long itemId,@RequestParam String requestId,
            @RequestParam String location,@RequestParam String description,@RequestParam(required=false) List<MultipartFile> files) throws Exception {
        return R.ok(service.report(taskId,itemId,requestId,location,description,files));
    }
    @GetMapping("/media/{mediaId}") public ResponseEntity<Resource> media(@PathVariable Long taskId,@PathVariable String mediaId) {
        Map<String,Object> media=service.media(taskId,mediaId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(media.get("media_type"))))
                .cacheControl(CacheControl.noStore()).header("X-Content-Type-Options","nosniff")
                .body((Resource)media.get("resource"));
    }
    private Long itemId(Map<String,Object> body) {
        try { return Long.valueOf(String.valueOf(body.get("itemId"))); }
        catch(Exception ex) { throw new ServiceException("请选择巡检项",400); }
    }
}
