package com.ruoyi.fuda;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/** Push credentials and device grants are independent of the query API. */
@Component
@ConfigurationProperties(prefix = "fuda.push")
public class FudaPushProperties {
    private boolean enabled;
    private String destinationId = "fuda";
    private String appId = "";
    private String secretBase64 = "";
    private String endpoint = "";
    private Map<String, String> endpoints = new LinkedHashMap<>();
    private boolean allowLoopbackHttp;
    private Set<String> allowedLedgerDeviceIds = new LinkedHashSet<>();
    private int connectTimeoutMillis = 2000;
    private int requestTimeoutMillis = 5000;
    private long leaseMillis = 30000;
    private int batchSize = 50;
    private long retryBaseMillis = 1000;
    private long retryMaxMillis = 300000;
    private long minSendIntervalMillis = 100;

    /** Disabled deployments need no receiver or credentials. */
    @PostConstruct
    public void validate() {
        if (!enabled) return;
        if (destinationId == null || !destinationId.matches("[A-Za-z0-9_-]{1,64}")) invalid();
        if (appId == null || !appId.matches("[A-Za-z0-9_-]{1,64}")) invalid();
        try {
            if (secretBase64 == null || Base64.getDecoder().decode(secretBase64).length != 32) invalid();
        } catch (IllegalArgumentException e) { invalid(); }
        if (allowedLedgerDeviceIds == null || allowedLedgerDeviceIds.isEmpty() || allowedLedgerDeviceIds.size() > 1000) invalid();
        for (String id : allowedLedgerDeviceIds) if (blank(id) || id.length() > 128) invalid();
        range(connectTimeoutMillis, 1, 60000);
        range(requestTimeoutMillis, 1, 300000);
        range(leaseMillis, (long) requestTimeoutMillis + 5000, 3600000);
        range(batchSize, 1, 10000);
        range(retryBaseMillis, 1, 300000);
        range(retryMaxMillis, retryBaseMillis, 300000);
        range(minSendIntervalMillis, 0, 300000);
        if (!blank(endpoint)) validatedUri(endpoint);
        for (Map.Entry<String, String> entry : endpoints.entrySet()) {
            if (!isKind(entry.getKey())) invalid();
            validatedUri(entry.getValue());
        }
        for (String kind : Arrays.asList("POSITION", "STATUS", "ALARM")) endpointFor(kind);
    }

    public URI endpointFor(String kind) {
        if (!isKind(kind)) throw new IllegalArgumentException("Unsupported push event type");
        String override = endpoints.get(kind);
        return validatedUri(override == null ? endpoint : override);
    }

    private URI validatedUri(String value) {
        if (blank(value)) throw new IllegalArgumentException("Invalid push endpoint");
        try {
            URI uri = new URI(value);
            String host = uri.getHost();
            boolean https = "https".equalsIgnoreCase(uri.getScheme());
            boolean loopback = "127.0.0.1".equals(host) || "::1".equals(host) || "[::1]".equals(host);
            boolean localHttp = allowLoopbackHttp && "http".equalsIgnoreCase(uri.getScheme()) && loopback;
            if ((!https && !localHttp) || host == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || uri.getPort() == 0 || uri.getPort() > 65535) {
                throw new IllegalArgumentException("Invalid push endpoint");
            }
            // HTTP always transmits '/' for an empty path; sign those same bytes.
            return uri.getRawPath().isEmpty() ? new URI(value + "/") : uri;
        } catch (URISyntaxException e) {
            throw new IllegalArgumentException("Invalid push endpoint");
        }
    }

    private static boolean isKind(String kind) {
        return "POSITION".equals(kind) || "STATUS".equals(kind) || "ALARM".equals(kind);
    }
    private static boolean blank(String value) { return value == null || value.trim().isEmpty(); }
    private static void range(long value, long minimum, long maximum) {
        if (value < minimum || value > maximum) invalid();
    }
    private static void invalid() { throw new IllegalArgumentException("Invalid Fuda push configuration"); }

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean value) { enabled = value; }
    public String getDestinationId() { return destinationId; }
    public void setDestinationId(String value) { destinationId = value; }
    public String getAppId() { return appId; }
    public void setAppId(String value) { appId = value; }
    public String getSecretBase64() { return secretBase64; }
    public void setSecretBase64(String value) { secretBase64 = value; }
    public String getEndpoint() { return endpoint; }
    public void setEndpoint(String value) { endpoint = value; }
    public Map<String, String> getEndpoints() { return endpoints; }
    public void setEndpoints(Map<String, String> value) { endpoints = value == null ? new LinkedHashMap<>() : value; }
    public boolean isAllowLoopbackHttp() { return allowLoopbackHttp; }
    public void setAllowLoopbackHttp(boolean value) { allowLoopbackHttp = value; }
    public Set<String> getAllowedLedgerDeviceIds() { return allowedLedgerDeviceIds; }
    public void setAllowedLedgerDeviceIds(Set<String> value) { allowedLedgerDeviceIds = value == null ? new LinkedHashSet<>() : value; }
    public int getConnectTimeoutMillis() { return connectTimeoutMillis; }
    public void setConnectTimeoutMillis(int value) { connectTimeoutMillis = value; }
    public int getRequestTimeoutMillis() { return requestTimeoutMillis; }
    public void setRequestTimeoutMillis(int value) { requestTimeoutMillis = value; }
    public long getLeaseMillis() { return leaseMillis; }
    public void setLeaseMillis(long value) { leaseMillis = value; }
    public int getBatchSize() { return batchSize; }
    public void setBatchSize(int value) { batchSize = value; }
    public long getRetryBaseMillis() { return retryBaseMillis; }
    public void setRetryBaseMillis(long value) { retryBaseMillis = value; }
    public long getRetryMaxMillis() { return retryMaxMillis; }
    public void setRetryMaxMillis(long value) { retryMaxMillis = value; }
    public long getMinSendIntervalMillis() { return minSendIntervalMillis; }
    public void setMinSendIntervalMillis(long value) { minSendIntervalMillis = value; }
}
