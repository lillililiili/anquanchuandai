package com.ruoyi.fuda;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class FudaAuthTest {
    static final Clock CLOCK=Clock.fixed(Instant.parse("2026-10-27T08:00:00Z"),ZoneOffset.UTC);
    static final byte[] KEY=new byte[32];
    static FudaProperties properties(){FudaProperties p=new FudaProperties();p.setEnabled(true);FudaProperties.Application a=new FudaProperties.Application();a.setEnabled(true);a.setSecretBase64(Base64.getEncoder().encodeToString(KEY));a.setAllowedLedgerDeviceIds(new HashSet<>(Arrays.asList("device-12","device-13")));p.getApplications().put("fuda-test",a);return p;}
    static MockHttpServletRequest signed(String body,String nonce){
        MockHttpServletRequest r=new MockHttpServletRequest("POST","/openapi/wearables/v2/positions/query");r.setContentType("application/json");
        r.setContent(body.getBytes(StandardCharsets.UTF_8));String timestamp=String.valueOf(CLOCK.instant().getEpochSecond());
        r.addHeader("X-App-Id","fuda-test");r.addHeader("X-Timestamp",timestamp);r.addHeader("X-Nonce",nonce);
        r.addHeader("X-Signature",FudaAuth.hmac(KEY,"POST\n"+r.getRequestURI()+"\nfuda-test\n"+timestamp+"\n"+nonce+"\n"+FudaAuth.sha256(body.getBytes(StandardCharsets.UTF_8))));return r;
    }
    @Test void originalBytesAndDecodedKeyAreAuthoritative(){
        FudaAuth a=new FudaAuth(properties(),(app,nonce)->true,CLOCK);String body="{\"devices\":[]}";
        assertEquals("fuda-test",a.authenticate(signed(body,UUID.randomUUID().toString()),body.getBytes(StandardCharsets.UTF_8)).appId);
        assertEquals(40101,assertThrows(FudaException.class,()->a.authenticate(signed(body,UUID.randomUUID().toString()),(body+" ").getBytes(StandardCharsets.UTF_8))).code);
    }
    @Test void matchesPublishedIndependentPythonVector(){
        byte[] publicKey=new byte[32];for(int i=0;i<32;i++)publicKey[i]=(byte)i;
        String body="{\"devices\":[{\"deviceType\":\"HELMET\",\"deviceId\":\"DEMO-HELMET-01\"}]}";
        assertEquals("0d35e198f6f8dbe3f43179d683eccd4426e374dd1f521f6d88b7d2f56b077ab1",FudaAuth.sha256(body.getBytes(StandardCharsets.UTF_8)));
        String canonical="POST\n/openapi/wearables/v2/positions/query\nfuda-public-test\n1793088000\n00000000-0000-4000-8000-000000000001\n"+FudaAuth.sha256(body.getBytes(StandardCharsets.UTF_8));
        assertEquals("ccb3b8436b45026ee3b4568cca0d86f4e06736937b02f702e5ddf21bf88abdc6",FudaAuth.hmac(publicKey,canonical));
    }
    @Test void rejectsExpiredFutureReplayAndHumanSessions(){
        Set<String> seen=new HashSet<>();FudaAuth a=new FudaAuth(properties(),(app,nonce)->seen.add(app+nonce),CLOCK);
        String body="{}",nonce=UUID.randomUUID().toString();MockHttpServletRequest r=signed(body,nonce);a.authenticate(r,body.getBytes(StandardCharsets.UTF_8));
        assertEquals(40902,assertThrows(FudaException.class,()->a.authenticate(r,body.getBytes(StandardCharsets.UTF_8))).code);
        MockHttpServletRequest old=signed(body,UUID.randomUUID().toString());old.removeHeader("X-Timestamp");old.addHeader("X-Timestamp",CLOCK.instant().minusSeconds(301).getEpochSecond());
        assertEquals(40102,assertThrows(FudaException.class,()->a.authenticate(old,body.getBytes(StandardCharsets.UTF_8))).code);
        MockHttpServletRequest human=signed(body,UUID.randomUUID().toString());human.addHeader("X-Wearable-Token","human-token");
        assertEquals(40101,assertThrows(FudaException.class,()->a.authenticate(human,body.getBytes(StandardCharsets.UTF_8))).code);
    }
    @Test void disabledMisconfiguredAndDuplicateHeadersFailClosed(){
        FudaProperties p=properties();p.setEnabled(false);FudaAuth a=new FudaAuth(p,(app,nonce)->true,CLOCK);String body="{}";
        assertEquals(50302,assertThrows(FudaException.class,()->a.authenticate(signed(body,UUID.randomUUID().toString()),body.getBytes())).code);
        p.setEnabled(true);p.getApplications().get("fuda-test").setSecretBase64("not-a-32-byte-key");
        assertEquals(50303,assertThrows(FudaException.class,()->a.authenticate(signed(body,UUID.randomUUID().toString()),body.getBytes())).code);
        MockHttpServletRequest r=signed(body,UUID.randomUUID().toString());r.addHeader("X-App-Id","other");
        assertEquals(40101,assertThrows(FudaException.class,()->a.authenticate(r,body.getBytes())).code);
    }
    @Test void cursorsAreBoundToAppKeyScopeAndCannotBeAltered(){
        FudaProperties p=properties();FudaAuth.Principal actor=new FudaAuth.Principal("fuda-test",p.getApplications().get("fuda-test"),KEY);
        Set<String> scope=new HashSet<>(Arrays.asList("HELMET:real-1","SAFETY_BELT:real-2"));String cursor=FudaCursor.encode(actor,scope,23);
        assertEquals(23,FudaCursor.decode(actor,scope,cursor));assertEquals(0,FudaCursor.decode(actor,scope,null));
        assertThrows(FudaException.class,()->FudaCursor.decode(actor,Collections.singleton("HELMET:real-1"),cursor));
        assertThrows(FudaException.class,()->FudaCursor.decode(new FudaAuth.Principal("other",actor.application,KEY),scope,cursor));
        assertThrows(FudaException.class,()->FudaCursor.decode(actor,scope,cursor+"0"));
    }
}
