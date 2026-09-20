package com.ruoyi.portal;
import java.math.BigDecimal;
import com.ruoyi.portal.PortalModels.*;
/** Pure conversion only; never invokes a legacy controller or a device platform. */
public final class PortalLegacyAdapter {
    private PortalLegacyAdapter() {}
    public static String id(Long value) { return value==null?null:value.toString(); }
    public static Communication communication(String status,boolean platformQuery,String observedAt) {
        Communication c=new Communication();c.sourceKind=platformQuery?"PLATFORM_QUERY":"LEGACY_SNAPSHOT";
        c.observedAt=platformQuery?observedAt:null;c.reasonCode="SOURCE_TIME_MISSING";
        if(platformQuery) c.state="1".equals(status)?CommunicationState.ONLINE:"0".equals(status)?CommunicationState.OFFLINE:CommunicationState.UNKNOWN;
        return c;
    }
    public static Reading battery(BigDecimal value,boolean percentageSemanticsConfirmed) {
        Reading r=new Reading();r.reasonCode="SOURCE_SEMANTICS_UNCONFIRMED";
        if(percentageSemanticsConfirmed&&value!=null&&value.compareTo(BigDecimal.ZERO)>=0&&value.compareTo(new BigDecimal("100"))<=0) {
            r.value=value.doubleValue();r.reasonCode="SOURCE_TIME_MISSING";
        }
        return r;
    }
}

