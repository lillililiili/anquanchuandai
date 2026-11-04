package com.ruoyi.cluster;
/** Task 2 replaces/extends this with the global maintenance operation lease.
* Called inside admission transaction, and again immediately before socket write. */
public interface ClusterCommandGuard {
    void admit(String deviceId);
    void dispatch(String commandId);
}
