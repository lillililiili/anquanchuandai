package com.ruoyi.melhat;

import java.util.*;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.apache.ibatis.builder.MapperBuilderAssistant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class EventFilterTest
{
    private final EventQueryService service = new EventQueryService();
    private final WearSafetyEventMapper events = mock(WearSafetyEventMapper.class);
    private final SiteAccessService access = mock(SiteAccessService.class);

    @BeforeEach void setup()
    {
        TableInfoHelper.initTableInfo(new MapperBuilderAssistant(new MybatisConfiguration(), ""), WearSafetyEvent.class);
        EventAccessService eventAccess = new EventAccessService();
        com.ruoyi.common.core.domain.model.LoginUser login = new com.ruoyi.common.core.domain.model.LoginUser();
        login.setUserId(100L);
        when(access.requireLogin()).thenReturn(login);
        when(access.isPlatformAdmin(any())).thenReturn(true);
        ReflectionTestUtils.setField(eventAccess, "sites", access);
        ReflectionTestUtils.setField(service, "eventAccess", eventAccess);
        ReflectionTestUtils.setField(service, "eventMapper", events);
        ReflectionTestUtils.setField(service, "siteAccessService", access);
        ReflectionTestUtils.setField(service, "commandService", mock(EventCommandService.class));
        when(access.listScopeSiteIds()).thenReturn(Arrays.asList(1L));
    }

    @Test void optionsUseAuthorizedSnapshotsAndDeduplicateCodes()
    {
        WearSafetyEvent a = new WearSafetyEvent(); a.setAlarmCode("helmet.new_code"); a.setAlarmName("平台新增名称");
        WearSafetyEvent b = new WearSafetyEvent(); b.setAlarmCode("belt.new_code");
        when(events.selectList(any())).thenAnswer(call -> {
            LambdaQueryWrapper<?> q = call.getArgument(0);
            assertTrue(q.getSqlSegment().contains("site_id IN"));
            assertTrue(q.getParamNameValuePairs().containsValue(1L));
            return Arrays.asList(a, a, b);
        });
        List<Map<String, String>> options = service.filterOptions();
        assertEquals(2, options.size());
        assertEquals("平台新增名称", options.get(0).get("label"));
        assertEquals("belt.new_code", options.get(1).get("label"));
        verify(access, atLeastOnce()).requireLogin();
    }

    @Test void noAuthorizedSitesReturnsNoOptionsOrEvents()
    {
        when(access.listScopeSiteIds()).thenReturn(Collections.emptyList());
        assertTrue(service.filterOptions().isEmpty());
        verifyNoInteractions(events);
    }

    @Test void combinesAlarmDeviceTaskAndSiteFiltersBeforePagination()
    {
        when(events.selectPage(any(Page.class), any())).thenAnswer(call -> {
            LambdaQueryWrapper<?> q = call.getArgument(1);
            String sql = q.getSqlSegment();
            assertTrue(sql.contains("alarm_code ="));
            assertTrue(sql.contains("site_id IN"));
            assertTrue(sql.contains("task_id ="));
            assertTrue(sql.contains(" OR "));
            assertFalse(sql.contains("helmet.new_code"));
            Collection<?> params = q.getParamNameValuePairs().values();
            assertTrue(params.containsAll(Arrays.asList(1L, 9L, "helmet.new_code", "helmet", "belt")));
            return new Page<WearSafetyEvent>(1, 20, 0);
        });
        service.page(1, 20, null, null, null, null, null, null, null,
                null, null, "9", null, null, "helmet.new_code", "helmet,belt");
        verify(events).selectPage(any(Page.class), any());
    }

    @Test void invalidDeviceTypeCannotEnterSql()
    {
        assertThrows(ServiceException.class, () -> service.page(1, 20, null, null, null, null,
                null, null, null, null, null, null, null, null, null, "helmet,' OR 1=1"));
        verifyNoInteractions(events);
    }

    @Test void multiStatusAndTypeUseGroupedUnionWithOtherConstraints()
    {
        when(events.selectPage(any(Page.class), any())).thenAnswer(call -> {
            LambdaQueryWrapper<?> q = call.getArgument(1);
            String sql = q.getSqlSegment();
            assertTrue(sql.contains("status IN"));
            assertTrue(sql.contains("event_type IN"));
            assertTrue(sql.contains(" OR alarm_code IN"));
            assertFalse(sql.contains("status <>"), "explicit states must allow closed events");
            assertTrue(sql.contains("person_id ="));
            assertTrue(sql.contains("site_id IN"));
            Collection<?> params = q.getParamNameValuePairs().values();
            assertTrue(params.containsAll(Arrays.asList("open", "closed", "fall", "impact",
                    "helmet.removal", "belt.unhooked", 7L)));
            return new Page<WearSafetyEvent>(1, 20, 0);
        });
        service.page(1, 20, null, null, "7", null, null, null, null,
                null, null, null, null, null, null, "helmet,belt",
                "open,closed", "fall,impact", "helmet.removal,belt.unhooked");
    }

    @Test void invalidMultiStatusRejected()
    {
        assertThrows(ServiceException.class, () -> service.page(1, 20, null, null, null, null,
                null, null, null, null, null, null, null, null, null, null,
                "open,invented", null, null));
        verifyNoInteractions(events);
    }
}
