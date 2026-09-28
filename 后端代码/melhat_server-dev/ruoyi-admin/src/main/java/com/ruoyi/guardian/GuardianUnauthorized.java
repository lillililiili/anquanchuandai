package com.ruoyi.guardian;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.UNAUTHORIZED)
public class GuardianUnauthorized extends RuntimeException {
    public GuardianUnauthorized(String message) {
        super(message);
    }
}
