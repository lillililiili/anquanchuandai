package com.ruoyi.cluster;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
@Component @ConfigurationProperties(prefix="melhat.cluster") public class ClusterProperties {
    private boolean enabled;
    private String nodeId;
    private long leaseMillis=30000,pollMillis=500,sendTimeoutMillis=3000,commandTimeoutMillis=60000;
    public void validate() {
        if(!enabled)return;
        if(nodeId==null||!nodeId.matches("[A-Za-z0-9_.-]{1,80}"))throw new IllegalStateException("Cluster requires a stable unique melhat.cluster.node-id");
        if(leaseMillis<3000||leaseMillis>120000||pollMillis<100||pollMillis>5000||sendTimeoutMillis<100||sendTimeoutMillis>10000||sendTimeoutMillis>=leaseMillis||commandTimeoutMillis<1000||commandTimeoutMillis>600000)throw new IllegalStateException("Invalid bounded cluster lease/poll/send/command timeout");
    }
    public boolean isEnabled() {
        return enabled;
    }
    public void setEnabled(boolean v) {
        enabled=v;
    }
    public String getNodeId() {
        return nodeId;
    }
    public void setNodeId(String v) {
        nodeId=v;
    }
    public long getLeaseMillis() {
        return leaseMillis;
    }
    public void setLeaseMillis(long v) {
        leaseMillis=v;
    }
    public long getPollMillis() {
        return pollMillis;
    }
    public void setPollMillis(long v) {
        pollMillis=v;
    }
    public long getSendTimeoutMillis() {
        return sendTimeoutMillis;
    }
    public void setSendTimeoutMillis(long v) {
        sendTimeoutMillis=v;
    }
    public long getCommandTimeoutMillis() {
        return commandTimeoutMillis;
    }
    public void setCommandTimeoutMillis(long v) {
        commandTimeoutMillis=v;
    }
}
