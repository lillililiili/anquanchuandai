package com.ruoyi.portal;
public class PortalException extends RuntimeException {
    public final int status; public final String errorCode;
    public PortalException(int status,String code,String message) { super(message);this.status=status;this.errorCode=code; }
    public static PortalException invalid() { return new PortalException(400,"VALIDATION_ERROR","请求参数不正确"); }
    public static PortalException forbidden() { return new PortalException(403,"FORBIDDEN","当前账号无权访问"); }
    public static PortalException missing() { return new PortalException(404,"PERSON_NOT_FOUND","人员不存在或不可见"); }
}

