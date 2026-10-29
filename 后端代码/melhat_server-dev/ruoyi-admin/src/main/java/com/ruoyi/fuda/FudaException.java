package com.ruoyi.fuda;
public class FudaException extends RuntimeException {
    public final int status,code;
    public FudaException(int status,int code,String message){super(message);this.status=status;this.code=code;}
    static FudaException bad(String message){return new FudaException(400,40001,message);}
}
