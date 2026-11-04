package com.ruoyi.guardian;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.annotation.Order;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.dao.TransientDataAccessResourceException;
import org.springframework.data.redis.RedisSystemException;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.CannotCreateTransactionException;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.LinkedHashMap;
import java.util.Map;

/** Keep wearable dependency outages separate from the legacy HTTP 200 error contract. */
@Order(1)
@RestControllerAdvice(assignableTypes = {GuardianController.class, GuardianMobileController.class,
        GuardianMobileCommunications.class, GuardianLocationController.class, GuardianHelmetMediaController.class,
        AdminLedgerController.class, WearableBusinessController.class, WearableMaintenanceController.class})
public class WearableDependencyError {
    private static final Logger LOG = LoggerFactory.getLogger(WearableDependencyError.class);

    @ExceptionHandler({DataAccessResourceFailureException.class, TransientDataAccessResourceException.class,
            QueryTimeoutException.class, RedisSystemException.class, CannotCreateTransactionException.class,
            TransactionSystemException.class})
    public ResponseEntity<Map<String, Object>> unavailable(Exception error) {
        LOG.warn("Wearable API dependency unavailable ({})", error.getClass().getSimpleName());
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", 503);
        body.put("errorCode", "SERVICE_UNAVAILABLE");
        body.put("message", "服务暂不可用，请稍后重试");
        return ResponseEntity.status(503).body(body);
    }
}
