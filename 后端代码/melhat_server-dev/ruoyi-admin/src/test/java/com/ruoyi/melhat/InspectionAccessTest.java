package com.ruoyi.melhat;

import java.util.*;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.work.InspectionService;
import com.ruoyi.wear.work.WorkTaskService;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class InspectionAccessTest {
    @Test void sameSiteNonMemberCannotReadTaskOrListWholeSite() {
        WorkTaskService service=service(false, Collections.singleton(7L), 1L);
        assertEquals(403,assertThrows(ServiceException.class,()->service.detail(9L)).getCode());
        assertEquals(403,assertThrows(ServiceException.class,()->service.page(1,20,null,null)).getCode());
        assertEquals(7L,service.requireReadable(7L).getId());
    }
    @Test void adminStillCannotReadAcrossSelectedSite() {
        WorkTaskService service=service(true, Collections.emptySet(), 2L);
        assertEquals(403,assertThrows(ServiceException.class,()->service.requireReadable(7L)).getCode());
    }
    @Test void mediaTypesAreValidatedByContentsNotFilename() {
        assertEquals("image/jpeg",InspectionService.mediaType(new byte[]{(byte)255,(byte)216,(byte)255,0}));
        assertEquals("image/png",InspectionService.mediaType(new byte[]{(byte)137,80,78,71,13,10,26,10}));
        assertEquals("video/mp4",InspectionService.mediaType(new byte[]{0,0,0,20,102,116,121,112,105,115,111,109}));
        assertThrows(ServiceException.class,()->InspectionService.mediaType("<script>fake.jpg</script>".getBytes()));
        assertThrows(ServiceException.class,()->InspectionService.mediaType(new byte[0]));
    }
    private WorkTaskService service(boolean admin,Set<Long> groups,Long site) {
        WorkTaskService service=spy(new WorkTaskService());
        SiteAccessService access=mock(SiteAccessService.class);
        LoginUser user=new LoginUser(); SysUser account=new SysUser(); account.setUserId(21L); user.setUser(account); user.setUserId(21L);
        when(access.requireLogin()).thenReturn(user);
        when(access.isPlatformAdmin(user)).thenReturn(admin);
        when(access.listScopeSiteIds()).thenReturn(Collections.singletonList(1L));
        WearWorkTaskMapper mapper=mock(WearWorkTaskMapper.class);
        for(long id:new long[]{7,9}) { WearWorkTask task=new WearWorkTask();task.setId(id);task.setSiteId(site);when(mapper.selectById(id)).thenReturn(task); }
        ReflectionTestUtils.setField(service,"taskMapper",mapper);
        ReflectionTestUtils.setField(service,"siteAccessService",access);
        doReturn(groups).when(service).memberTaskIds();
        return service;
    }
}
