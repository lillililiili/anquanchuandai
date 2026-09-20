package com.ruoyi.portal;
import org.springframework.web.bind.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.core.Ordered;
import org.springframework.http.ResponseEntity;
import com.ruoyi.portal.PortalModels.Envelope;
@RestControllerAdvice(basePackages="com.ruoyi.portal")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class PortalExceptionHandler {
    @ExceptionHandler(PortalException.class)
    public ResponseEntity<Envelope<Object>> handle(PortalException e) {
        return ResponseEntity.status(e.status).body(new Envelope<>(e.status,e.getMessage(),e.errorCode,null));
    }
    @ExceptionHandler({org.springframework.dao.DataIntegrityViolationException.class,org.springframework.dao.ConcurrencyFailureException.class})
    public ResponseEntity<Envelope<Object>> conflict(Exception e) {
        return ResponseEntity.status(409).body(new Envelope<>(409,"数据已变化，请刷新后重试","DATA_CONFLICT",null));
    }
    @ExceptionHandler({org.springframework.web.bind.MissingRequestHeaderException.class,org.springframework.web.bind.MissingServletRequestParameterException.class,org.springframework.http.converter.HttpMessageNotReadableException.class})
    public ResponseEntity<Envelope<Object>> invalid(Exception e) {
        return ResponseEntity.status(400).body(new Envelope<>(400,"请求参数不完整或格式错误","INVALID_QUERY",null));
    }
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Envelope<Object>> unexpected(Exception e) {
        return ResponseEntity.status(500).body(new Envelope<>(500,"服务暂时不可用","INTERNAL_ERROR",null));
    }
}
