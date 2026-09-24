package com.ruoyi.melhat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ruoyi.wear.event.EventStateMachine;
import com.ruoyi.wear.event.EventViews;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import java.util.Map;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class EventVerificationBoundaryTest {
    @Test void reviewEndpointCannotAcceptAnExternalClosureWrite() throws Exception {
        com.ruoyi.wear.web.v1.WearEventController controller = new com.ruoyi.wear.web.v1.WearEventController();
        com.ruoyi.wear.event.EventCommandService commands = org.mockito.Mockito.mock(com.ruoyi.wear.event.EventCommandService.class);
        org.springframework.test.util.ReflectionTestUtils.setField(controller,"commandService",commands);
        WearSafetyEvent event = new WearSafetyEvent(); event.setStatus("verified"); event.setSeverity("emergency");
        org.mockito.Mockito.when(commands.close(1L,"通过",3)).thenReturn(EventViews.toDto(event));
        org.springframework.test.web.servlet.MockMvc mvc = org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(controller).build();
        for (String endpoint : new String[]{"review", "close"}) {
            mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/api/v1/events/1/"+endpoint)
                    .contentType("application/json").content("{\"reason\":\"通过\",\"version\":3,\"externalClosureStatus\":\"closed\"}"))
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isOk())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath("$.data.status").value("verified"))
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath("$.data.externalClosureStatus").value("not_synced"));
        }
    }

    @Test void mapperPersistsVerificationAndConfirmationWithoutClosingACase() {
        org.springframework.jdbc.datasource.DriverManagerDataSource source = new org.springframework.jdbc.datasource.DriverManagerDataSource(
                "jdbc:h2:mem:" + java.util.UUID.randomUUID() + ";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "");
        org.springframework.jdbc.core.JdbcTemplate db = new org.springframework.jdbc.core.JdbcTemplate(source);
        db.execute("CREATE TABLE wear_safety_event(id BIGINT,status VARCHAR,version INT,update_by VARCHAR,update_time TIMESTAMP,claimant_user_id BIGINT)");
        db.execute("INSERT INTO wear_safety_event VALUES(1,'pending_review',3,null,null,null),(2,'open',1,null,null,null)");
        com.baomidou.mybatisplus.core.MybatisConfiguration config = new com.baomidou.mybatisplus.core.MybatisConfiguration();
        config.setEnvironment(new org.apache.ibatis.mapping.Environment("test", new org.apache.ibatis.transaction.jdbc.JdbcTransactionFactory(), source));
        config.addMapper(com.ruoyi.wear.event.mapper.WearSafetyEventMapper.class);
        try (org.apache.ibatis.session.SqlSession session = new org.apache.ibatis.session.SqlSessionFactoryBuilder().build(config).openSession(true)) {
            com.ruoyi.wear.event.mapper.WearSafetyEventMapper mapper = session.getMapper(com.ruoyi.wear.event.mapper.WearSafetyEventMapper.class);
            assertEquals(0, mapper.closeIfStatus(1L,"pending_review",2,"admin"));
            assertEquals(1, mapper.closeIfStatus(1L,"pending_review",3,"admin"));
            assertEquals("verified", db.queryForObject("SELECT status FROM wear_safety_event WHERE id=1",String.class));
            assertEquals(0, mapper.closeIfStatus(1L,"pending_review",3,"admin"));
            assertEquals(1, mapper.confirmIfStatus(2L,"open",1,"owner"));
            assertEquals("confirmed", db.queryForObject("SELECT status FROM wear_safety_event WHERE id=2",String.class));
            assertEquals(1, mapper.reopenIfClosed(1L,4,"admin"));
            assertEquals("open", db.queryForObject("SELECT status FROM wear_safety_event WHERE id=1",String.class));
        }
    }

    @Test void reviewAndFieldSubmissionRemainSeparateAndLegacyIsNotReinterpreted() {
        WearSafetyEvent event = new WearSafetyEvent();
        event.setStatus("pending_review"); event.setSeverity("emergency"); event.setEventType("sos");
        assertEquals("submitted", EventViews.toDto(event).getFieldReportStatus());
        assertEquals("pending", EventViews.toDto(event).getReviewStatus());
        event.setStatus("verified");
        assertEquals("approved", EventViews.toDto(event).getReviewStatus());
        event.setStatus("closed");
        assertEquals("unknown", EventViews.toDto(event).getFieldReportStatus());
        assertEquals("unknown", EventViews.toDto(event).getReviewStatus());
        event.setStatus("confirmed"); event.setSeverity("warning"); event.setEventType("realtime");
        assertEquals("not_required", EventViews.toDto(event).getVerificationStatus());
        assertEquals("not_synced", EventViews.toDto(event).getExternalClosureStatus());
    }

    @Test void fieldVerificationNeverMeansExternalClosure() {
        assertEquals("verified", EventStateMachine.handleTarget("abnormal"));
        assertEquals("pending_review", EventStateMachine.handleTarget("emergency"));
        for (String status : new String[]{"open", "pending_review", "verified", "closed"}) {
            WearSafetyEvent event = new WearSafetyEvent();
            event.setStatus(status); event.setSeverity("emergency"); event.setEventType("sos");
            Map<?, ?> dto = new ObjectMapper().convertValue(EventViews.toDto(event), Map.class);
            assertEquals("not_synced", dto.get("externalClosureStatus"));
            assertEquals("closed".equals(status) ? "unknown" :
                    "verified".equals(status) ? "verified" : "pending", dto.get("verificationStatus"));
        }
    }
}
