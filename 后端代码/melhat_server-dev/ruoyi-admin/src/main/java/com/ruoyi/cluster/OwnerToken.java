package com.ruoyi.cluster;
/** Immutable identity only; never contains a socket or credentials. */
public final class OwnerToken {
    public final String deviceType,deviceId,nodeId,generation,connectionToken;
    public OwnerToken(String type,String id,String node,String generation,String token) {
        deviceType=type;
        deviceId=id;
        nodeId=node;
        this.generation=generation;
        connectionToken=token;
    }
}
