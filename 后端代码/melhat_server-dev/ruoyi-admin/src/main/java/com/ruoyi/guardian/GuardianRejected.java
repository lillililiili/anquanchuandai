package com.ruoyi.guardian;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.BAD_REQUEST)
public class GuardianRejected extends RuntimeException {
    public GuardianRejected(String message) {
        super(message);
    }
}
