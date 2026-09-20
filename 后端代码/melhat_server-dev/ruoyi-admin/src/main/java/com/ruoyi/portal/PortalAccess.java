package com.ruoyi.portal;
import org.springframework.stereotype.Component;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.core.domain.model.LoginUser;
@Component
public class PortalAccess {
    private LoginUser user() {
        try {
            LoginUser user=SecurityUtils.getLoginUser();
            if(user==null || user.getUserId()==null) throw new IllegalStateException();
            return user;
        } catch(Exception e) { throw new PortalException(401,"UNAUTHENTICATED","请先登录"); }
    }
    public String actorId() { return String.valueOf(user().getUserId()); }
    public boolean has(String permission) {
        java.util.Set<String> values=user().getPermissions();
        return values!=null && (values.contains(permission)||values.contains("*:*:*"));
    }
    public void require(String permission) { if(!has(permission)) throw PortalException.forbidden(); }
}

