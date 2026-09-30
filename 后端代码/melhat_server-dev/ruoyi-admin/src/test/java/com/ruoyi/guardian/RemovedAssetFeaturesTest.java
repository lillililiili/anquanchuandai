package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RemovedAssetFeaturesTest {
    @Test void rejectsAllRemovedCommandsBeforeDispatchOrStorage() {
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);
        AdminQueryService queries=mock(AdminQueryService.class);
        AdminDeviceService devices=mock(AdminDeviceService.class);
        AdminAssignmentService assignments=mock(AdminAssignmentService.class);
        AdminMaintenanceService maintenance=mock(AdminMaintenanceService.class);
        AdminMasterService master=mock(AdminMasterService.class);
        AdminAccessService access=mock(AdminAccessService.class);
        AdminLedgerController controller=new AdminLedgerController(ledger,queries,devices,assignments,maintenance,master,access);
        MockHttpServletRequest request=new MockHttpServletRequest();
        request.setAttribute("wearable.actor",JSONObject.parseObject("{\"id\":\"demo-system\"}"));
        for (String type : new String[]{"maintenance.create","maintenance.assign","maintenance.start","maintenance.inspect","maintenance.scrap","devices.disable","devices.restore","devices.scrap"}) {
            JSONObject body=new JSONObject();body.put("type",type);body.put("input",new JSONObject());
            assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->controller.execute(body,request)).code);
        }
        JSONObject body=JSONObject.parseObject("{\"type\":\"assignments.return\",\"input\":{\"items\":[{\"condition\":\"REPAIR\"}]}}");
        assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->controller.execute(body,request)).code);
        // Spring/Jackson also produces nested Maps rather than Fastjson JSONObjects.
        com.alibaba.fastjson2.JSONArray mappedItems=new com.alibaba.fastjson2.JSONArray();
        mappedItems.add(java.util.Collections.singletonMap("condition","REPAIR"));
        body.getJSONObject("input").put("items",mappedItems);
        assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->controller.execute(body,request)).code);
        verifyNoInteractions(ledger,queries,devices,assignments,maintenance,master,access);
    }

    @Test void removedQueriesAndRepairFieldsAreRejectedWhileNormalFlowsRemainAllowed() {
        for(String kind:new String[]{"maintenanceOrders","maintenanceOrder","maintenanceSummary","maintenanceRecords","repairAssignees","deviceLifecycleHistory"})
            assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->RemovedAssetFeatures.requireQuery(kind,null)).code);
        assertThrows(AdminQueryService.QueryFailed.class,()->RemovedAssetFeatures.requireQuery("details",JSONObject.parseObject("{\"metric\":\"maintenance\"}")));
        assertThrows(AdminQueryService.QueryFailed.class,()->RemovedAssetFeatures.requireCommand("assignments.return",JSONObject.parseObject("{\"items\":[{\"condition\":\"GOOD\",\"handlerId\":\"old-handler\"}]}")));
        for(String type:new String[]{"devices.create","devices.update","devices.configure","assignments.issue","assignments.return"})
            assertDoesNotThrow(()->RemovedAssetFeatures.requireCommand(type,JSONObject.parseObject("{\"items\":[{\"condition\":\"GOOD\"}]}")));
        assertDoesNotThrow(()->RemovedAssetFeatures.requireQuery("devices",null));
    }
}
