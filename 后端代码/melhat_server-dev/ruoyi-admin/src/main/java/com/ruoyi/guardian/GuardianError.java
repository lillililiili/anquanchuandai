package com.ruoyi.guardian;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice(assignableTypes = GuardianController.class)
public class GuardianError {
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
