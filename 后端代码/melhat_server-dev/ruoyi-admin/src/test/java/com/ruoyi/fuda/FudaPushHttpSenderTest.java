package com.ruoyi.fuda;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;

import static org.junit.jupiter.api.Assertions.*;

class FudaPushHttpSenderTest {
    private static final byte[] KEY = new byte[32];
    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-11-02T12:00:00Z"), ZoneOffset.UTC);
    private HttpServer server;
    private ExecutorService executor;
    private FudaPushProperties properties;

    @BeforeEach void startLoopbackReceiver() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        executor = Executors.newCachedThreadPool();
        server.setExecutor(executor);
        server.start();
        properties = validProperties();
        properties.setEndpoint(url("/push"));
        properties.setAllowLoopbackHttp(true);
    }

    @AfterEach void stopLoopbackReceiver() {
        if (server != null) server.stop(0);
        if (executor != null) executor.shutdownNow();
    }

    @Test void defaultConfigurationIsDisabledAndSafeToValidate() {
        FudaPushProperties p = new FudaPushProperties();
        assertFalse(p.isEnabled());
        assertEquals("fuda", p.getDestinationId());
        assertEquals(2000, p.getConnectTimeoutMillis());
        assertEquals(5000, p.getRequestTimeoutMillis());
        assertEquals(30000, p.getLeaseMillis());
        assertEquals(50, p.getBatchSize());
        assertEquals(1000, p.getRetryBaseMillis());
        assertEquals(300000, p.getRetryMaxMillis());
        assertEquals(100, p.getMinSendIntervalMillis());
        assertTrue(p.getAllowedLedgerDeviceIds().isEmpty());
        assertDoesNotThrow(p::validate);
        assertEquals("DISABLED", new FudaPushHttpSender(p, CLOCK).send("POSITION", new byte[0]).outcome);
    }

    @Test void signsExactBytesRawPathAndFreshNonceOnEveryAttempt() throws Exception {
        byte[] body = "{\"eventId\":\"稳定事件\", \"value\":1}\n".getBytes(StandardCharsets.UTF_8);
        List<String> nonces = Collections.synchronizedList(new ArrayList<>());
        List<String> signatures = Collections.synchronizedList(new ArrayList<>());
        List<byte[]> received = Collections.synchronizedList(new ArrayList<>());
        List<String> contentTypes = Collections.synchronizedList(new ArrayList<>());
        properties.setEndpoint(url("/push/%E4%BD%8D%E7%BD%AE"));
        server.createContext("/push", exchange -> {
            byte[] sentBody = read(exchange.getRequestBody());
            String nonce = exchange.getRequestHeaders().getFirst("X-Nonce");
            String app = exchange.getRequestHeaders().getFirst("X-App-Id");
            String timestamp = exchange.getRequestHeaders().getFirst("X-Timestamp");
            received.add(sentBody);
            nonces.add(nonce);
            signatures.add(exchange.getRequestHeaders().getFirst("X-Signature"));
            contentTypes.add(exchange.getRequestHeaders().getFirst("Content-Type"));
            assertEquals("POST", exchange.getRequestMethod());
            assertEquals("fuda-push-test", app);
            assertEquals(String.valueOf(CLOCK.instant().getEpochSecond()), timestamp);
            assertEquals(FudaAuth.hmac(KEY, "POST\n" + exchange.getRequestURI().getRawPath() + "\n" + app
                    + "\n" + timestamp + "\n" + nonce + "\n" + FudaAuth.sha256(sentBody)),
                    exchange.getRequestHeaders().getFirst("X-Signature"));
            reply(exchange, nonces.size() == 1 ? 503 : 200, "{\"code\":0}");
        });
        FudaPushHttpSender sender = new FudaPushHttpSender(properties, CLOCK);
        assertFalse(sender.send("POSITION", body).success);
        assertTrue(sender.send("POSITION", body).success);
        assertEquals(2, received.size());
        for (byte[] bytes : received) assertArrayEquals(body, bytes);
        for (String nonce : nonces) assertEquals(nonce, UUID.fromString(nonce).toString());
        assertNotEquals(nonces.get(0), nonces.get(1));
        assertNotEquals(signatures.get(0), signatures.get(1));
        assertEquals(Arrays.asList("application/json; charset=utf-8", "application/json; charset=utf-8"), contentTypes);
    }

    @ParameterizedTest
    @ValueSource(strings = {"{\"code\":\"0\"}", "{\"code\":0.0}", "{\"code\":0e0}", "{\"code\":false}",
            "{\"code\":null}", "{}", "[]", "broken-json", "{\"code\":0} trailing", "{\"code\":0,\"code\":1}", ""})
    void requiresStrictIntegerAcknowledgement(String response) {
        server.createContext("/push", exchange -> reply(exchange, 200, response));
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertFalse(result.success);
        assertEquals(200, result.httpStatus);
        assertEquals("INVALID_RESPONSE", result.outcome);
    }

    @Test void zeroIntegerIsAcceptedAndNonzeroCodeIsRejected() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> reply(exchange, 200,
                requests.incrementAndGet() == 1 ? "{\"code\":0,\"message\":\"accepted\"}" : "{\"code\":7}"));
        FudaPushHttpSender sender = sender();
        assertTrue(sender.send("ALARM", bytes("{}")).success);
        assertEquals("RECEIVER_REJECTED", sender.send("ALARM", bytes("{}")).outcome);
    }

    @Test void otherSuccessfulHttpStatusDoesNotAcknowledge() {
        server.createContext("/push", exchange -> reply(exchange, 201, "{\"code\":0}"));
        FudaPushHttpSender.Result result = sender().send("POSITION", bytes("{}"));
        assertFalse(result.success);
        assertEquals(201, result.httpStatus);
        assertEquals("HTTP_STATUS", result.outcome);
    }

    @Test void redirectIsNeverFollowed() {
        AtomicInteger redirected = new AtomicInteger();
        server.createContext("/push", exchange -> {
            exchange.getResponseHeaders().add("Location", url("/redirected"));
            reply(exchange, 302, "{\"code\":0}");
        });
        server.createContext("/redirected", exchange -> {
            redirected.incrementAndGet();
            reply(exchange, 200, "{\"code\":0}");
        });
        FudaPushHttpSender.Result result = sender().send("POSITION", bytes("{}"));
        assertFalse(result.success);
        assertEquals(302, result.httpStatus);
        assertEquals(0, redirected.get());
    }

    @Test void connectionFailureDoesNotAutomaticallyRetry() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> { requests.incrementAndGet(); exchange.close(); });
        assertFalse(sender().send("STATUS", bytes("{}")).success);
        assertEquals(1, requests.get());
    }

    @Test void serviceUnavailableWithImmediateRetryAfterStillMakesOnlyOneAttempt() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> {
            requests.incrementAndGet();
            exchange.getResponseHeaders().add("Retry-After", "0");
            reply(exchange, 503, "{}");
        });
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertFalse(result.success);
        assertEquals(503, result.httpStatus);
        assertEquals(0, result.retryAfterMillis);
        assertEquals(1, requests.get());
    }

    @Test void timeoutIncludesSlowHeaders() {
        properties.setRequestTimeoutMillis(250);
        server.createContext("/push", exchange -> {
            pause(1500);
            reply(exchange, 200, "{\"code\":0}");
        });
        long started = System.nanoTime();
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertEquals("TIMEOUT", result.outcome);
        assertTrue((System.nanoTime() - started) / 1000000 < 1400);
    }

    @Test void totalCallTimeoutAlsoBoundsTricklingResponseBody() {
        properties.setRequestTimeoutMillis(300);
        server.createContext("/push", exchange -> {
            exchange.sendResponseHeaders(200, 0);
            try {
                for (byte b : bytes("{\"code\":0}")) {
                    exchange.getResponseBody().write(b);
                    exchange.getResponseBody().flush();
                    pause(90);
                }
            } catch (IOException ignored) { /* client timed out */ }
            finally { exchange.close(); }
        });
        long started = System.nanoTime();
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertEquals("TIMEOUT", result.outcome);
        assertTrue((System.nanoTime() - started) / 1000000 < 1400);
    }

    @Test void responseBodyHasHardLimitEvenForChunkedTransfer() {
        server.createContext("/push", exchange -> {
            exchange.sendResponseHeaders(200, 0);
            try { exchange.getResponseBody().write(new byte[16385]); }
            finally { exchange.close(); }
        });
        FudaPushHttpSender.Result result = sender().send("ALARM", bytes("{}"));
        assertFalse(result.success);
        assertEquals("RESPONSE_TOO_LARGE", result.outcome);
    }

    @Test void acceptsExactlySixteenKiBResponse() {
        char[] padding = new char[16384 - "{\"code\":0}".length()];
        Arrays.fill(padding, ' ');
        server.createContext("/push", exchange -> reply(exchange, 200, "{\"code\":0}" + new String(padding)));
        assertTrue(sender().send("STATUS", bytes("{}")).success);
    }

    @Test void deeplyNestedResponseWithinByteLimitDoesNotCrashWorker() {
        String nested = String.join("", Collections.nCopies(7000, "[")) + "0"
                + String.join("", Collections.nCopies(7000, "]"));
        server.createContext("/push", exchange -> reply(exchange, 200, "{\"code\":0,\"extra\":" + nested + "}"));
        assertTrue(sender().send("STATUS", bytes("{}")).success);
    }

    @ParameterizedTest @ValueSource(ints = {429, 503})
    void honorsCappedRetryAfterSeconds(int status) {
        server.createContext("/push", exchange -> {
            exchange.getResponseHeaders().add("Retry-After", "999999999999999999999");
            reply(exchange, status, "private receiver error");
        });
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertFalse(result.success);
        assertEquals(status, result.httpStatus);
        assertEquals("HTTP_STATUS", result.outcome);
        assertEquals(300000, result.retryAfterMillis);
    }

    @Test void honorsHttpDateRetryAfterAndIgnoresUnrelatedStatus() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> {
            exchange.getResponseHeaders().add("Retry-After", DateTimeFormatter.RFC_1123_DATE_TIME
                    .format(CLOCK.instant().plusSeconds(12).atZone(ZoneOffset.UTC)));
            reply(exchange, requests.incrementAndGet() == 1 ? 503 : 500, "{}");
        });
        FudaPushHttpSender sender = sender();
        assertEquals(12000, sender.send("STATUS", bytes("{}")).retryAfterMillis);
        assertEquals(0, sender.send("STATUS", bytes("{}")).retryAfterMillis);
    }

    @Test void malformedOrPastRetryAfterIsIgnored() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> {
            exchange.getResponseHeaders().add("Retry-After", requests.incrementAndGet() == 1 ? "-1" : "nonsense");
            reply(exchange, 429, "{}");
        });
        FudaPushHttpSender sender = sender();
        assertEquals(0, sender.send("STATUS", bytes("{}")).retryAfterMillis);
        assertEquals(0, sender.send("STATUS", bytes("{}")).retryAfterMillis);
    }

    @ParameterizedTest @ValueSource(strings = {"http://example.com/push", "http://localhost/push", "http://127.1/push",
            "https://user:password@example.com/push", "https://example.com/push?x=1", "https://example.com/push#part",
            "ftp://example.com/push", "https:///push", "https://example.com:0/push", "https://example.com:65536/push"})
    void rejectsUnsafeEndpoints(String endpoint) {
        properties.setEndpoint(endpoint);
        assertThrows(IllegalArgumentException.class, properties::validate);
    }

    @Test void endpointOverridesAndLoopbackHttpRequireExplicitOptIn() {
        FudaPushProperties p = validProperties();
        p.getEndpoints().put("ALARM", "https://alarm.example.com/receive");
        assertEquals("https://alarm.example.com/receive", p.endpointFor("ALARM").toString());
        assertEquals("https://example.com/push", p.endpointFor("POSITION").toString());
        p.setEndpoint("http://127.0.0.1/push");
        assertThrows(IllegalArgumentException.class, p::validate);
        p.setAllowLoopbackHttp(true);
        assertDoesNotThrow(p::validate);
        p.setEndpoint("http://[::1]/push");
        assertDoesNotThrow(p::validate);
        p.getEndpoints().put("STATUS", "http://192.168.0.1/push");
        assertThrows(IllegalArgumentException.class, p::validate);
        assertThrows(IllegalArgumentException.class, () -> p.endpointFor("UNKNOWN"));
    }

    @Test void rejectsMissingCredentialsWhitelistAndInvalidNumericConfiguration() {
        List<Consumer<FudaPushProperties>> invalid = Arrays.asList(
                p -> p.setDestinationId(" "), p -> p.setAppId(""), p -> p.setAppId("bad\r\nheader"),
                p -> p.setSecretBase64("invalid"), p -> p.setSecretBase64(Base64.getEncoder().encodeToString(new byte[31])),
                p -> p.setAllowedLedgerDeviceIds(Collections.emptySet()),
                p -> p.setAllowedLedgerDeviceIds(Collections.singleton(" ")), p -> p.setEndpoint(""),
                p -> p.setConnectTimeoutMillis(0), p -> p.setRequestTimeoutMillis(0),
                p -> p.setLeaseMillis(p.getRequestTimeoutMillis()), p -> p.setBatchSize(0),
                p -> p.setBatchSize(10001), p -> p.setRetryBaseMillis(0), p -> p.setRetryMaxMillis(300001),
                p -> p.setRetryMaxMillis(p.getRetryBaseMillis() - 1), p -> p.setMinSendIntervalMillis(-1));
        for (Consumer<FudaPushProperties> mutation : invalid) {
            FudaPushProperties p = validProperties();
            mutation.accept(p);
            assertThrows(IllegalArgumentException.class, p::validate);
        }
    }

    @Test void invalidConfigurationFailsClosedWithoutSendingAndOutcomesDoNotExposeSecrets() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/push", exchange -> { requests.incrementAndGet(); reply(exchange, 200, "{\"code\":0}"); });
        properties.setSecretBase64("private-value");
        FudaPushHttpSender.Result result = sender().send("STATUS", bytes("{}"));
        assertEquals("CONFIG_INVALID", result.outcome);
        assertEquals(0, result.httpStatus);
        assertEquals(0, requests.get());
        assertFalse(result.outcome.contains("private-value"));
    }

    @Test void destinationAndDeviceGrantScopeRespectOutboxStorageBounds() {
        FudaPushProperties p = validProperties();
        p.setDestinationId(String.join("", Collections.nCopies(65, "a")));
        assertThrows(IllegalArgumentException.class, p::validate);
        p.setDestinationId("invalid destination");
        assertThrows(IllegalArgumentException.class, p::validate);
        p.setDestinationId(String.join("", Collections.nCopies(64, "a")));
        assertDoesNotThrow(p::validate);
        p.setAllowedLedgerDeviceIds(Collections.singleton(String.join("", Collections.nCopies(129, "a"))));
        assertThrows(IllegalArgumentException.class, p::validate);
        p.setAllowedLedgerDeviceIds(Collections.singleton(String.join("", Collections.nCopies(128, "a"))));
        assertDoesNotThrow(p::validate);
        Set<String> ids = new LinkedHashSet<>();
        for (int i = 0; i < 1000; i++) ids.add("device-" + i);
        p.setAllowedLedgerDeviceIds(ids);
        assertDoesNotThrow(p::validate);
        ids.add("device-1000");
        assertThrows(IllegalArgumentException.class, p::validate);
    }

    private FudaPushHttpSender sender() { return new FudaPushHttpSender(properties, CLOCK); }
    private String url(String path) { return "http://127.0.0.1:" + server.getAddress().getPort() + path; }
    private static byte[] bytes(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static FudaPushProperties validProperties() {
        FudaPushProperties p = new FudaPushProperties();
        p.setEnabled(true);
        p.setAppId("fuda-push-test");
        p.setSecretBase64(Base64.getEncoder().encodeToString(KEY));
        p.setAllowedLedgerDeviceIds(Collections.singleton("real-device-1"));
        p.setEndpoint("https://example.com/push");
        return p;
    }
    private static byte[] read(InputStream input) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        byte[] buffer = new byte[1024];
        int size;
        while ((size = input.read(buffer)) != -1) result.write(buffer, 0, size);
        return result.toByteArray();
    }
    private static void reply(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = bytes(body);
        exchange.sendResponseHeaders(status, bytes.length == 0 ? -1 : bytes.length);
        try { exchange.getResponseBody().write(bytes); }
        finally { exchange.close(); }
    }
    private static void pause(long millis) {
        try { Thread.sleep(millis); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
