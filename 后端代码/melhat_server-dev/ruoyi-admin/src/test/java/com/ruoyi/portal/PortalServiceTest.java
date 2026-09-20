package com.ruoyi.portal;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.common.core.domain.model.LoginUser;
import org.junit.jupiter.api.*;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PortalServiceTest {
    PortalSource source; PortalAccess access; PortalService service; MockMvc mvc; Context context;
    @BeforeEach void setup() {
        source=mock(PortalSource.class);access=new PortalAccess();login("portal:person:read","portal:person:history");
        service=new PortalService(source,access);
        mvc=MockMvcBuilders.standaloneSetup(new PortalController(service)).setControllerAdvice(new PortalExceptionHandler()).build();
        context=new Context(); Site site=new Site();site.siteId="site-a";site.name="合成厂站";context.sites.add(site);
        Shift shift=new Shift();shift.shiftId="shift-a";shift.siteId="site-a";shift.isCurrent=true;context.shifts.add(shift);
        context.availability.put("roster",State.AVAILABLE);
        when(source.context(anyString())).thenReturn(context);
        when(source.roster(anyString(),anyString(),anyString())).thenReturn(Section.available(new ArrayList<>()));
        when(source.person(anyString(),eq("site-a"),eq("person-a"))).thenAnswer(i->person("person-a"));
        when(source.equipment(anyString(),anyString(),anyList())).thenReturn(Collections.emptyMap());
        when(source.history(anyString(),anyString(),anyString())).thenReturn(Section.missing("HISTORY_NOT_INTEGRATED"));
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }
    void login(String...permissions) {
        LoginUser user=new LoginUser();user.setUserId(101L);user.setPermissions(new HashSet<>(Arrays.asList(permissions)));
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(user,null,Collections.emptyList()));
    }
    Person person(String id) {Person p=new Person();p.personId=id;p.siteId="site-a";p.name="合成人员";return p;}
    PortalQuery query() {PortalQuery q=new PortalQuery();q.siteId="site-a";return q;}
    @Test void defaultSourceHasNoAuthorityOrFakePeople() {
        PortalSource fallback=new PortalSourceConfiguration().portalSource();
        assertTrue(fallback.context("101").sites.isEmpty());
        assertEquals(State.NOT_INTEGRATED,fallback.roster("101","site-a","shift-a").state);
        assertNull(fallback.person("101","site-a","person-a"));
        assertTrue(fallback.equipment("101","site-a",Collections.emptyList()).isEmpty());
    }
    @Test void contextRequiresLogin() throws Exception {
        SecurityContextHolder.clearContext();
        mvc.perform(get("/api/portal/v1/context")).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.errorCode").value("UNAUTHENTICATED"));
        verifyNoInteractions(source);
    }
    @Test void contextReturnsOnlyFrontPermissions() throws Exception {
        login("portal:person:read","system:user:list");
        mvc.perform(get("/api/portal/v1/context")).andExpect(status().isOk()).andExpect(jsonPath("$.data.permissions.length()").value(1)).andExpect(jsonPath("$.requestId").isString());
    }
    @Test void readPermissionCannotBeSkipped() throws Exception {
        login();
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a")).andExpect(status().isForbidden());
        verifyNoInteractions(source);
    }
    @Test void historyRequiresBothPermissions() throws Exception {
        login("portal:person:history");
        mvc.perform(get("/api/portal/v1/people/person-a/equipment-history").param("siteId","site-a")).andExpect(status().isForbidden());
    }
    @Test void wildcardPermissionStillRequiresSite() throws Exception {
        login("*:*:*");
        mvc.perform(get("/api/portal/v1/people").param("siteId","other")).andExpect(status().isForbidden());
        verify(source,never()).roster(anyString(),anyString(),anyString());
    }
    @Test void invalidAndDuplicateParameters() throws Exception {
        for(String value:Arrays.asList("0","101","-1","abc","1.5")) mvc.perform(get("/api/portal/v1/people").param("siteId","site-a").param("pageSize",value)).andExpect(status().isBadRequest());
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a").param("sort","name")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a","other")).andExpect(status().isBadRequest());
    }
    @Test void emptyRosterIsZero() throws Exception {
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a")).andExpect(status().isOk()).andExpect(jsonPath("$.data.total").value(0)).andExpect(jsonPath("$.data.state").value("AVAILABLE"));
    }
    @Test void unintegratedRosterIsNotZero() throws Exception {
        context.availability.put("roster",State.NOT_INTEGRATED);
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a")).andExpect(status().isOk()).andExpect(jsonPath("$.data.state").value("NOT_INTEGRATED")).andExpect(jsonPath("$.data.total").doesNotExist());
        verify(source,never()).roster(anyString(),anyString(),anyString());
    }
    @Test void ambiguousShiftDoesNotUseAllUsers() {
        context.shifts.clear();
        assertEquals("SHIFT_UNRESOLVED",service.people(query()).reasonCode);
        verify(source,never()).roster(anyString(),anyString(),anyString());
    }
    @Test void rejectsUnknownTeamAndShift() throws Exception {
        for(String key:Arrays.asList("teamId","shiftId"))mvc.perform(get("/api/portal/v1/people").param("siteId","site-a").param(key,"other")).andExpect(status().isBadRequest());
    }
    @Test void pagesAfterNameFilterAndStableSort() {
        Person a=person("person-a"),b=person("person-b");a.personCode="002";b.personCode="001";
        when(source.roster(anyString(),anyString(),anyString())).thenReturn(Section.available(Arrays.asList(a,b)));
        PortalQuery q=query();q.pageSize=1;
        Page<Person> page=service.people(q);
        assertEquals(2L,page.total);assertEquals("person-b",page.items.get(0).personId);
        verify(source,times(1)).equipment(eq("101"),eq("site-a"),eq(Collections.singletonList("person-b")));
    }
    @Test void coreFailureIs503() throws Exception {
        when(source.roster(anyString(),anyString(),anyString())).thenThrow(new IllegalStateException("private failure"));
        mvc.perform(get("/api/portal/v1/people").param("siteId","site-a")).andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.errorCode").value("SOURCE_UNAVAILABLE"));
    }
    @Test void equipmentFailureIsPartial() throws Exception {
        when(source.equipment(anyString(),anyString(),anyList())).thenThrow(new IllegalStateException());
        mvc.perform(get("/api/portal/v1/people/person-a").param("siteId","site-a")).andExpect(status().isOk()).andExpect(jsonPath("$.data.equipment.state").value("UNAVAILABLE")).andExpect(jsonPath("$.data.person.equipment.state").value("UNAVAILABLE"));
    }
    @Test void foreignPersonAndMissingPersonAre404() throws Exception {
        Person p=person("person-a");p.siteId="other";
        when(source.person(anyString(),anyString(),eq("person-a"))).thenReturn(p);
        for(String id:Arrays.asList("person-a","missing"))mvc.perform(get("/api/portal/v1/people/"+id).param("siteId","site-a")).andExpect(status().isNotFound());
        verify(source,never()).history(anyString(),anyString(),anyString());
    }
    @Test void historyPermissionHidesSummary() throws Exception {
        login("portal:person:read");
        mvc.perform(get("/api/portal/v1/people/person-a").param("siteId","site-a")).andExpect(jsonPath("$.data.historySummary.state").value("FORBIDDEN")).andExpect(jsonPath("$.data.actions.viewHistory.allowed").value(false));
        verify(source,never()).history(anyString(),anyString(),anyString());
    }
    @Test void snapshotDoesNotFabricateHistoryDates() throws Exception {
        History h=new History();h.recordId="record-a";h.personId="person-a";h.deviceType=DeviceType.HELMET;h.action="MIGRATION_SNAPSHOT";h.startedAt="2026-01-01T00:00:00Z";
        when(source.history(anyString(),anyString(),anyString())).thenReturn(Section.available(Collections.singletonList(h)));
        mvc.perform(get("/api/portal/v1/people/person-a/equipment-history").param("siteId","site-a")).andExpect(status().isOk()).andExpect(jsonPath("$.data.items[0].startedAt").doesNotExist()).andExpect(jsonPath("$.data.items[0].evidenceQuality").value("CURRENT_SNAPSHOT_ONLY"));
        assertEquals(0L,service.detail(query(),"person-a").historySummary.data.total);
    }
    @Test void historyWithWrongOwnerFailsClosed() throws Exception {
        History h=new History();h.recordId="record-a";h.personId="someone-else";h.deviceType=DeviceType.HELMET;
        when(source.history(anyString(),anyString(),anyString())).thenReturn(Section.available(Collections.singletonList(h)));
        mvc.perform(get("/api/portal/v1/people/person-a/equipment-history").param("siteId","site-a")).andExpect(status().isServiceUnavailable());
    }
    @Test void defaultNoScopeNeverReadsRoster() {
        when(source.context(anyString())).thenReturn(new Context());
        assertEquals(403,assertThrows(PortalException.class,()->service.people(query())).status);
        verify(source,never()).roster(anyString(),anyString(),anyString());
    }
    Equipment equipment(String deviceId) {
        Equipment e=new Equipment();e.helmet=new Slot();e.helmet.type=DeviceType.HELMET;
        e.belt=new Slot();e.belt.type=DeviceType.BELT;e.watch=new Slot();e.watch.type=DeviceType.WATCH;
        Device d=new Device();d.type=DeviceType.HELMET;d.deviceId=deviceId;d.deviceCode="SYN-H";
        e.helmet.assignmentState=Assignment.ASSIGNED;e.helmet.devices.add(d);return e;
    }
    @Test void pureLegacyAdapterDoesNotClaimCacheIsOnline() {
        assertEquals("9007199254740993",PortalLegacyAdapter.id(9007199254740993L));
        assertEquals(CommunicationState.UNKNOWN,PortalLegacyAdapter.communication("1",false,null).state);
        assertEquals(CommunicationState.OFFLINE,PortalLegacyAdapter.communication("0",true,null).state);
        assertEquals(Freshness.UNKNOWN,PortalLegacyAdapter.communication("1",true,null).freshness);
        assertNull(PortalLegacyAdapter.battery(new java.math.BigDecimal("80"),false).value);
    }
    @Test void historySortUsesInstantsNotMixedPrecisionStrings() {
        History a=new History();a.recordId="a";a.personId="person-a";a.deviceType=DeviceType.HELMET;a.evidenceQuality="CONFIRMED";a.action="ISSUE";a.occurredAt="2026-01-01T00:00:00Z";
        History b=new History();b.recordId="b";b.personId="person-a";b.deviceType=DeviceType.HELMET;b.evidenceQuality="CONFIRMED";b.action="RETURN";b.occurredAt="2026-01-01T00:00:00.500Z";
        when(source.history(anyString(),anyString(),anyString())).thenReturn(Section.available(Arrays.asList(a,b)));
        assertEquals("b",service.history(query(),"person-a").items.get(0).recordId);
        assertEquals(b.occurredAt,service.detail(query(),"person-a").historySummary.data.lastOccurredAt);
    }
    @Test void localStatusAndMissingSourceTimeRemainUnknown() {
        Equipment e=equipment("device-a");Device d=e.helmet.devices.get(0);
        d.communication.sourceKind="LEGACY_SNAPSHOT";d.communication.state=CommunicationState.ONLINE;d.communication.freshness=Freshness.FRESH;
        when(source.equipment(anyString(),anyString(),anyList())).thenReturn(Collections.singletonMap("person-a",Section.available(e)));
        Device result=service.detail(query(),"person-a").equipment.data.helmet.devices.get(0);
        assertEquals(CommunicationState.UNKNOWN,result.communication.state);assertEquals(Freshness.UNKNOWN,result.communication.freshness);
    }
    @Test void duplicateDeviceOwnersAreNotSilentlyAccepted() {
        when(source.roster(anyString(),anyString(),anyString())).thenReturn(Section.available(Arrays.asList(person("person-a"),person("person-b"))));
        Map<String,Section<Equipment>> eq=new HashMap<>();eq.put("person-a",Section.available(equipment("same")));eq.put("person-b",Section.available(equipment("same")));
        when(source.equipment(anyString(),anyString(),anyList())).thenReturn(eq);
        Page<Person> result=service.people(query());
        assertTrue(result.items.stream().allMatch(p->p.equipment.state==State.UNAVAILABLE&&"ASSIGNMENT_CONFLICT".equals(p.equipment.reasonCode)));
    }
    @Test void beltAssignmentDoesNotAuthorizeTelemetry() {
        Equipment e=equipment("device-a");Device belt=new Device();belt.deviceId="belt-a";belt.deviceCode="SYN-B";belt.type=DeviceType.BELT;
        belt.battery.value=99d;belt.communication.state=CommunicationState.ONLINE;
        e.belt.assignmentState=Assignment.ASSIGNED;e.belt.devices.add(belt);
        when(source.equipment(anyString(),anyString(),anyList())).thenReturn(Collections.singletonMap("person-a",Section.available(e)));
        Device result=service.detail(query(),"person-a").equipment.data.belt.devices.get(0);
        assertNull(result.battery.value);assertEquals(CommunicationState.NOT_INTEGRATED,result.communication.state);
    }
}
