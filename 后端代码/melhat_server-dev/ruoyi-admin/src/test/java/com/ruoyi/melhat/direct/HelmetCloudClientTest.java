package com.ruoyi.melhat.direct;
import org.junit.jupiter.api.Test;
import java.nio.charset.StandardCharsets;
import static org.junit.jupiter.api.Assertions.*;

class HelmetCloudClientTest {
    @Test void signatureMatchesNodeCryptoForUtf8BodyAndCompleteControlPath() throws Exception {
        String actual=HelmetCloudClient.signature("test-only-shared-key-0123456789abcdef","1792730000","test-nonce-123456789","POST","/helmet-media/control/v1/tts","{\"text\":\"安全帽\"}".getBytes(StandardCharsets.UTF_8));
        assertEquals("b9baa2d6c081652db32f7de9e0ebac44caf5bfda5c1e689471cf070f9657f69b",actual);
        assertNotEquals(actual,HelmetCloudClient.signature("test-only-shared-key-0123456789abcdef","1792730000","test-nonce-123456789","POST","/tts","{\"text\":\"安全帽\"}".getBytes(StandardCharsets.UTF_8)));
    }
    @Test void cloudControlRequiresEnabledHttpsAndPrivateKey(){
        HelmetMediaProperties p=new HelmetMediaProperties();HelmetCloudClient client=new HelmetCloudClient(p);
        assertFalse(client.configured());p.setEnabled(true);p.setControlUrl("https://media.example.test/helmet-media/control/v1");p.setSharedKey("test-only-shared-key-0123456789abcdef");assertTrue(client.configured());
        p.setControlUrl("http://media.example.test/control");assertFalse(client.configured());
        p.setControlUrl("https://credential@media.example.test/control");assertFalse(client.configured());
    }
}
