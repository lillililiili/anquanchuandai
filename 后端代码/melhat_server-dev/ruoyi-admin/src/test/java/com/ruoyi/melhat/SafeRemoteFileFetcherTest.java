package com.ruoyi.melhat;

import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.file.SafeRemoteFileFetcher;
import org.junit.jupiter.api.Test;

import java.net.InetAddress;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SafeRemoteFileFetcherTest {

    @Test
    void rejectsNonHttpProtocols() {
        SafeRemoteFileFetcher fetcher = SafeRemoteFileFetcher.defaults(false);
        assertThrows(ServiceException.class, () -> fetcher.validate("file:///etc/passwd"));
        assertThrows(ServiceException.class, () -> fetcher.validate("ftp://example.com/a.bin"));
        assertThrows(ServiceException.class, () -> fetcher.validate(""));
    }

    @Test
    void rejectsLoopbackAndPrivateWhenNotAllowed() throws Exception {
        SafeRemoteFileFetcher fetcher = SafeRemoteFileFetcher.defaults(false);
        assertTrue(fetcher.isForbiddenAddress(InetAddress.getByName("127.0.0.1")));
        assertTrue(fetcher.isForbiddenAddress(InetAddress.getByName("10.0.0.1")));
        assertTrue(fetcher.isForbiddenAddress(InetAddress.getByName("192.168.1.8")));
        assertTrue(fetcher.isForbiddenAddress(InetAddress.getByName("169.254.169.254")));
        assertThrows(ServiceException.class, () -> fetcher.validate("http://127.0.0.1/secret"));
    }

    @Test
    void allowsPrivateNetworkOnlyWhenConfigured() throws Exception {
        SafeRemoteFileFetcher fetcher = SafeRemoteFileFetcher.defaults(true);
        assertFalse(fetcher.isForbiddenAddress(InetAddress.getByName("10.0.0.1")));
        assertTrue(fetcher.isForbiddenAddress(InetAddress.getByName("169.254.169.254")));
    }
}
