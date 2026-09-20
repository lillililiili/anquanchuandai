package com.ruoyi.portal;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalS2Models.*;
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
class PortalS2Test {
    PortalSource context; PortalSpatialSource spatial; PortalMaterialSource media; PortalS2Service service; MockMvc mvc;
    String from="2026-09-17T00:00:00Z",to="2026-09-17T01:00:00Z";
    @BeforeEach void setup() {
        login("*:*:*"); context=mock(PortalSource.class);spatial=mock(PortalSpatialSource.class);media=mock(PortalMaterialSource.class);
        Context c=new Context();Site site=new Site();site.siteId="s";site.name="合成厂站";c.sites.add(site);when(context.context(anyString())).thenReturn(c);
        when(spatial.visible(anyString(),eq("s"),anyString(),anyString(),anyString())).thenAnswer(i->!"hidden".equals(i.getArgument(3)));
        when(media.visible(anyString(),eq("s"),anyString(),anyString())).thenAnswer(i->!"hidden".equals(i.getArgument(3)));
        when(spatial.devices(anyString(),anyString(),anySet())).thenReturn(Section.available(new ArrayList<>()));
        when(spatial.locations(anyString(),anyString())).thenReturn(Section.available(new ArrayList<>()));
        when(spatial.fences(anyString(),anyString())).thenReturn(Section.available(new ArrayList<>()));
        when(media.materials(anyString(),anyString())).thenReturn(Section.available(new ArrayList<>()));
        service=new PortalS2Service(new PortalAccess(),context,spatial,media);
        mvc=MockMvcBuilders.standaloneSetup(new PortalS2Controller(service)).setControllerAdvice(new PortalExceptionHandler()).build();
    }
    @AfterEach void cleanup(){SecurityContextHolder.clearContext();}
    void login(String...ps){LoginUser u=new LoginUser();u.setUserId(101L);u.setPermissions(new HashSet<>(Arrays.asList(ps)));SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(u,null,Collections.emptyList()));}
    PortalS2Query q(){PortalS2Query q=new PortalS2Query();q.siteId="s";q.deviceId="d";q.from=from;q.to=to;return q;}
    <T extends Item> T item(T t,String id){t.id=id;t.siteId="s";t.name="合成测试";return t;}
    Material material(){Material m=item(new Material(),"m");m.type="PHOTO";m.deviceId="d";m.personId="p";m.attribution="UNKNOWN";return m;}
    Track track(){Track t=item(new Track(),"t");t.deviceId="d";t.from=from;t.to=to;t.complete=true;return t;}
    @Test void defaultSourcesNeverProvideAuthorityOrSampleData(){PortalS2Configuration c=new PortalS2Configuration();assertFalse(c.portalSpatialSource().visible("a","s","device","d","portal:track:read"));assertEquals(State.NOT_INTEGRATED,c.portalSpatialSource().locations("a","s").state);assertEquals(State.NOT_INTEGRATED,c.portalMaterialSource().materials("a","s").state);}
    @Test void allSevenRoutesRequireLogin() throws Exception {SecurityContextHolder.clearContext();for(String path:Arrays.asList("devices","locations/latest","fences","fences/f","materials","materials/m","tracks?deviceId=d&from="+from+"&to="+to))mvc.perform(get("/api/portal/v1/"+path).param("siteId","s")).andExpect(status().isUnauthorized());verifyNoInteractions(context,spatial,media);}
    @Test void allPermissionsDenied() throws Exception {login();for(String path:Arrays.asList("devices","locations/latest","fences","fences/f","materials","materials/m","tracks?deviceId=d&from="+from+"&to="+to))mvc.perform(get("/api/portal/v1/"+path).param("siteId","s")).andExpect(status().isForbidden());}
    @Test void crossSiteDeniedEvenWithWildcard() throws Exception {for(String path:Arrays.asList("devices","locations/latest","fences","fences/f","materials","materials/m","tracks?deviceId=d&from="+from+"&to="+to))mvc.perform(get("/api/portal/v1/"+path).param("siteId","other")).andExpect(status().isForbidden());verifyNoInteractions(spatial,media);}
    @Test void listRoutesHaveEnvelopeAndPagination() throws Exception {for(String path:Arrays.asList("devices","locations/latest","fences","materials"))mvc.perform(get("/api/portal/v1/"+path).param("siteId","s")).andExpect(status().isOk()).andExpect(jsonPath("$.data.total").value(0)).andExpect(jsonPath("$.data.scope.siteId").value("s")).andExpect(jsonPath("$.requestId").isString());}
    @Test void detailRoutes() throws Exception {Fence f=item(new Fence(),"f");when(spatial.fence("101","s","f")).thenReturn(f);when(media.material("101","s","m")).thenReturn(material());mvc.perform(get("/api/portal/v1/fences/f").param("siteId","s")).andExpect(status().isOk()).andExpect(jsonPath("$.data.id").value("f"));mvc.perform(get("/api/portal/v1/materials/m").param("siteId","s")).andExpect(status().isOk()).andExpect(jsonPath("$.data.personId").doesNotExist()).andExpect(jsonPath("$.data.accessReason").value("FILE_ACCESS_NOT_ENABLED"));}
    @Test void trackRoute() throws Exception {when(spatial.tracks("101","s","d",from,to)).thenReturn(Section.available(track()));mvc.perform(get("/api/portal/v1/tracks").param("siteId","s").param("deviceId","d").param("from",from).param("to",to)).andExpect(status().isOk()).andExpect(jsonPath("$.data.data.complete").value(true));}
    @Test void invalidDuplicateAndUnknownParameters() throws Exception {for(String size:Arrays.asList("0","101","abc","1.2"))mvc.perform(get("/api/portal/v1/materials").param("siteId","s").param("pageSize",size)).andExpect(status().isBadRequest());mvc.perform(get("/api/portal/v1/fences").param("siteId","s","x")).andExpect(status().isBadRequest());mvc.perform(get("/api/portal/v1/devices").param("siteId","s").param("url","x")).andExpect(status().isBadRequest());mvc.perform(get("/api/portal/v1/tracks").param("siteId","s")).andExpect(status().isBadRequest());}
    @Test void unknownObjectsAre404() throws Exception {for(String path:Arrays.asList("fences/hidden","materials/hidden","fences/missing","materials/missing"))mvc.perform(get("/api/portal/v1/"+path).param("siteId","s")).andExpect(status().isNotFound());}
    @Test void sourceFaultIsNotEmptyOrUnintegrated() throws Exception {when(spatial.locations(anyString(),anyString())).thenThrow(new IllegalStateException("secret"));mvc.perform(get("/api/portal/v1/locations/latest").param("siteId","s")).andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.errorCode").value("SOURCE_UNAVAILABLE"));}
    @Test void missingSourceIsNotZero() {when(media.materials(anyString(),anyString())).thenReturn(Section.missing("MATERIAL_NOT_INTEGRATED"));Page<Material> result=service.materials(q());assertNull(result.total);assertTrue(result.items.isEmpty());assertEquals(State.NOT_INTEGRATED,result.state);}
    @Test void deviceOptionsFilteredByPurposeAndVisibility(){login("portal:track:read");DeviceOption a=item(new DeviceOption(),"d"),b=item(new DeviceOption(),"hidden");a.type=b.type=DeviceType.HELMET;when(spatial.devices(anyString(),anyString(),anySet())).thenReturn(Section.available(Arrays.asList(a,b)));assertEquals(1,service.devices(q()).total);verify(spatial).devices(eq("101"),eq("s"),eq(Collections.singleton("portal:track:read")));}
    @Test void historicalOwnerNotCurrentBinding(){Track t=track();t.personId="p";when(spatial.tracks(anyString(),anyString(),anyString(),anyString(),anyString())).thenReturn(Section.available(t));assertNull(service.tracks(q()).data.personId);PortalS2Query q=q();q.personId="p";assertEquals("HISTORICAL_ATTRIBUTION_UNKNOWN",service.tracks(q).reasonCode);}
    @Test void invisibleRelatedObjectsRemoved(){Material m=material();m.attribution="CONFIRMED";m.personId="hidden";m.workId="hidden";m.eventId="hidden";when(media.material("101","s","m")).thenReturn(m);Material result=service.material(q(),"m");assertNull(result.personId);assertNull(result.workId);assertNull(result.eventId);}
    @Test void metadataClassHasNoStorageOrAccessFields(){for(java.lang.reflect.Field f:Material.class.getFields())assertFalse(f.getName().toLowerCase().matches(".*(url|path|token).*"));}
    @Test void sourceTimeUnknownDoesNotUseReceiptTime(){LocatedDevice l=item(new LocatedDevice(),"loc");l.deviceId="d";l.position=new Position();l.position.receivedAt=from;l.position.freshness=Freshness.FRESH;when(spatial.locations(anyString(),anyString())).thenReturn(Section.available(Collections.singletonList(l)));assertEquals(Freshness.UNKNOWN,service.locations(q()).items.get(0).position.freshness);assertNull(l.position.sourceTime);}
    @Test void wrongSiteFromSourceRejected(){Fence f=item(new Fence(),"f");f.siteId="other";when(spatial.fences(anyString(),anyString())).thenReturn(Section.available(Collections.singletonList(f)));assertEquals(503,assertThrows(PortalException.class,()->service.fences(q())).status);}
    @Test void partialTrackRequiresExplicitReason(){Track t=track();t.complete=false;when(spatial.tracks(anyString(),anyString(),anyString(),anyString(),anyString())).thenReturn(Section.available(t));assertEquals(503,assertThrows(PortalException.class,()->service.tracks(q())).status);}
    @Test void longDeviceIdsRemainStrings() throws Exception {DeviceOption d=item(new DeviceOption(),"90071992547409931234");d.type=DeviceType.HELMET;when(spatial.devices(anyString(),anyString(),anySet())).thenReturn(Section.available(Collections.singletonList(d)));mvc.perform(get("/api/portal/v1/devices").param("siteId","s")).andExpect(jsonPath("$.data.items[0].id").value(d.id));}
    @Test void paginationFiltersBeforeCounting(){Fence a=item(new Fence(),"a"),b=item(new Fence(),"b");a.status="ENABLED";b.status="DISABLED";when(spatial.fences(anyString(),anyString())).thenReturn(Section.available(Arrays.asList(b,a)));PortalS2Query q=q();q.status="ENABLED";q.pageSize=1;assertEquals(1L,service.fences(q).total);q.pageNum=2;assertTrue(service.fences(q).items.isEmpty());}
    @Test void invalidTrackRanges() throws Exception {for(String end:Arrays.asList(from,"invalid","2026-09-16T00:00:00Z"))mvc.perform(get("/api/portal/v1/tracks").param("siteId","s").param("deviceId","d").param("from",from).param("to",end)).andExpect(status().isBadRequest());}
    @Test void deviceScopeCheckedBeforeTrackSource(){PortalS2Query q=q();q.deviceId="hidden";assertEquals(404,assertThrows(PortalException.class,()->service.tracks(q)).status);verify(spatial,never()).tracks(anyString(),anyString(),anyString(),anyString(),anyString());}
    @Test void unknownWorkEvidenceNeverCreatesAssociation(){Material m=material();m.workId="work";m.eventId="event";when(media.material("101","s","m")).thenReturn(m);Material result=service.material(q(),"m");assertNull(result.workId);assertNull(result.eventId);}
    @Test void trackLimitIsExplicitNotSilentTruncation(){Track t=track();Segment s=new Segment();s.segmentId="seg";for(int i=0;i<10001;i++)s.points.add(new Position());t.segments.add(s);when(spatial.tracks(anyString(),anyString(),anyString(),anyString(),anyString())).thenReturn(Section.available(t));PortalException e=assertThrows(PortalException.class,()->service.tracks(q()));assertEquals(422,e.status);assertEquals("RESULT_TOO_LARGE",e.errorCode);}
}
