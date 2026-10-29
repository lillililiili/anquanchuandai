package com.ruoyi.melhat.direct;

import com.ruoyi.guardian.GuardianIngest;
import com.ruoyi.helmet.mapper.RealTimeAlarmMapper;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.mapper.SafetyHatLocationRecordMapper;
import com.ruoyi.helmet.mapper.SosAlarmRecordMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DirectHelmetTransactionTest {
    @Test void transactionCommitsBeforeGuardianLockIsEnteredAndFailureNeverPublishes() {
        try (AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext(TxApp.class)) {
            TrackingTransactions tx = context.getBean(TrackingTransactions.class);
            SafetyHatLocationRecordMapper locations = context.getBean(SafetyHatLocationRecordMapper.class);
            GuardianIngest ingest = context.getBean(GuardianIngest.class);
            when(locations.insert(any(SafetyHatLocationRecord.class))).thenAnswer(call -> {
                assertTrue(TransactionSynchronizationManager.isActualTransactionActive());
                tx.events.add("write"); return 1;
            });
            doAnswer(call -> {
                assertFalse(TransactionSynchronizationManager.isActualTransactionActive());
                tx.events.add("publish"); return null;
            }).when(ingest).directLocation(any());
            SafetyHatInfo hat = new SafetyHatInfo(); hat.setId(1L); hat.setHatNumber("test-helmet");
            DirectHelmetMessage report = DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":35,\"y_point\":112}");
            DirectHelmetTelemetryService service = context.getBean(DirectHelmetTelemetryService.class);
            service.receive(hat, report);
            assertEquals(Arrays.asList("begin", "write", "commit", "publish"), tx.events);
            tx.events.clear(); clearInvocations(ingest);
            when(locations.insert(any(SafetyHatLocationRecord.class))).thenThrow(new IllegalStateException("storage unavailable"));
            assertThrows(IllegalStateException.class, () -> service.receive(hat, report));
            assertEquals(Arrays.asList("begin", "rollback"), tx.events);
            verify(ingest, never()).directLocation(any());
            verify(ingest, never()).projectDirectEvent(any());
        }
    }

    @Configuration
    @EnableTransactionManagement
    static class TxApp {
        @Bean TrackingTransactions transactionManager() { return new TrackingTransactions(); }
        @Bean SafetyHatInfoMapper hats() {
            SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
            when(mapper.updateById(any(SafetyHatInfo.class))).thenReturn(1);
            return mapper;
        }
        @Bean SafetyHatLocationRecordMapper locations() { return mock(SafetyHatLocationRecordMapper.class); }
        @Bean RealTimeAlarmMapper alarms() { return mock(RealTimeAlarmMapper.class); }
        @Bean SosAlarmRecordMapper sos() { return mock(SosAlarmRecordMapper.class); }
        @Bean GuardianIngest ingest() { return mock(GuardianIngest.class); }
        @Bean DirectHelmetPersistence persistence(SafetyHatInfoMapper hats, SafetyHatLocationRecordMapper locations,
                RealTimeAlarmMapper alarms, SosAlarmRecordMapper sos) {
            return new DirectHelmetPersistence(hats, locations, alarms, sos);
        }
        @Bean DirectHelmetTelemetryService telemetry(SafetyHatInfoMapper hats, DirectHelmetPersistence persistence,
                GuardianIngest ingest) { return new DirectHelmetTelemetryService(hats, persistence, ingest); }
    }

    static class TrackingTransactions extends AbstractPlatformTransactionManager {
        final List<String> events = new ArrayList<>();
        @Override protected Object doGetTransaction() { return new Object(); }
        @Override protected void doBegin(Object transaction, TransactionDefinition definition) { events.add("begin"); }
        @Override protected void doCommit(DefaultTransactionStatus status) { events.add("commit"); }
        @Override protected void doRollback(DefaultTransactionStatus status) { events.add("rollback"); }
    }
}
