package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import static com.ruoyi.guardian.WearableModel.*;

/** Capture from an already-authorized ledger device before sending any side effect. */
final class GuardianHelmetRecipient {
    private GuardianHelmetRecipient(){}
    static JSONObject capture(GuardianAccess.Context ctx,JSONObject device){
        String personId=null,name="未关联人员";
        for(Object raw:rows(ctx.data,"assignments")){JSONObject binding=(JSONObject)raw;
            if(binding.getBooleanValue("active")&&device.getString("id").equals(binding.getString("deviceId"))){
                JSONObject person=find(ctx.data,"people",binding.getString("personId"));
                if(person!=null){personId=person.getString("portalId");name=person.getString("name");}break;
            }
        }
        return object("hatNumber",device.getString("portalDeviceId"),"name",name,"siteId",device.get("siteId"),"areaId",device.get("areaId"),"personId",personId);
    }
}
