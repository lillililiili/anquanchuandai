package com.ruoyi.guardian;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice(assignableTypes = {GuardianController.class, GuardianMobileController.class, GuardianMobileCommunications.class})
public class GuardianError {
    @ExceptionHandler(AdminQueryService.QueryFailed.class)
    public ResponseEntity<Map<String,Object>> business(AdminQueryService.QueryFailed error) {
        Map<String,Object> body=new LinkedHashMap<>();body.put("code",error.code);body.put("errorCode",error.errorCode);body.put("message",error.getMessage());
        return ResponseEntity.status(error.code).body(body);
    }
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String,String>> invalid(IllegalArgumentException error) {
        Map<String,String> body=new LinkedHashMap<>();body.put("message",error.getMessage());return ResponseEntity.badRequest().body(body);
    }
    @ExceptionHandler(GuardianRejected.class)
    public ResponseEntity<Map<String, String>> rejected(GuardianRejected error) {
        Map<String, String> body = new LinkedHashMap<String, String>();
        body.put("message", error.getMessage());
        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler(GuardianUnauthorized.class)
    public ResponseEntity<Map<String, String>> unauthorized(GuardianUnauthorized error) {
        Map<String, String> body = new LinkedHashMap<String, String>();
        body.put("message", error.getMessage());
        return ResponseEntity.status(401).body(body);
    }
}
