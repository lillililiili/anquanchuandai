package com.ruoyi.fuda;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import okio.BufferedSink;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.net.URI;
import java.time.Clock;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** One bounded attempt. Durable retries and device authorization belong to the dispatcher. */
@Component
public class FudaPushHttpSender {
    private static final int RESPONSE_LIMIT = 16 * 1024;
    private static final long MAX_RETRY_AFTER_MILLIS = 300000;
    private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");
    private static final JsonFactory JSON_FACTORY = new JsonFactory().enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
    private final FudaPushProperties properties;
    private final Clock clock;
    private final OkHttpClient client;

    public FudaPushHttpSender(FudaPushProperties properties, @Qualifier("fudaClock") Clock clock) {
        this.properties = properties;
        this.clock = clock;
        this.client = new OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
                .retryOnConnectionFailure(false)
                .addNetworkInterceptor(chain -> {
                    Response response = chain.proceed(chain.request());
                    if (response.code() != 503) return response;
                    RetryMetadata metadata = chain.request().tag(RetryMetadata.class);
                    if (metadata != null) metadata.retryAfter = response.header("Retry-After");
                    // OkHttp 4.9.1 otherwise retries 503/Retry-After:0 even with retries disabled,
                    // and parses arbitrarily large seconds as int before returning the response.
                    return response.newBuilder().removeHeader("Retry-After").build();
                }).build();
    }

    public Result send(String eventType, byte[] body) {
        if (!properties.isEnabled()) return result(false, 0, "DISABLED", 0);
        URI endpoint;
        try {
            properties.validate();
            endpoint = properties.endpointFor(eventType);
        } catch (IllegalArgumentException e) {
            return result(false, 0, "CONFIG_INVALID", 0);
        }
        if (body == null) return result(false, 0, "INVALID_REQUEST", 0);
        // Snapshot bytes once so signing and transport see the same immutable payload.
        byte[] payload = body.clone();
        HttpUrl url = HttpUrl.get(endpoint.toASCIIString());
        String appId = properties.getAppId();
        String timestamp = String.valueOf(clock.instant().getEpochSecond());
        String nonce = UUID.randomUUID().toString();
        String canonical = "POST\n" + url.encodedPath() + "\n" + appId + "\n" + timestamp
                + "\n" + nonce + "\n" + FudaAuth.sha256(payload);
        String signature = FudaAuth.hmac(Base64.getDecoder().decode(properties.getSecretBase64()), canonical);
        RetryMetadata metadata = new RetryMetadata();
        RequestBody requestBody = new RequestBody() {
            @Override public MediaType contentType() { return JSON; }
            @Override public long contentLength() { return payload.length; }
            @Override public boolean isOneShot() { return true; }
            @Override public void writeTo(BufferedSink sink) throws IOException { sink.write(payload); }
        };
        Request request = new Request.Builder().url(url).post(requestBody).tag(RetryMetadata.class, metadata)
                .header("X-App-Id", appId).header("X-Timestamp", timestamp)
                .header("X-Nonce", nonce).header("X-Signature", signature).build();
        // newBuilder shares the connection pool but honors current timeout configuration.
        OkHttpClient bounded = client.newBuilder()
                .connectTimeout(properties.getConnectTimeoutMillis(), TimeUnit.MILLISECONDS)
                .readTimeout(properties.getRequestTimeoutMillis(), TimeUnit.MILLISECONDS)
                .writeTimeout(properties.getRequestTimeoutMillis(), TimeUnit.MILLISECONDS)
                .callTimeout(properties.getRequestTimeoutMillis(), TimeUnit.MILLISECONDS).build();
        int status = 0;
        try (Response response = bounded.newCall(request).execute()) {
            status = response.code();
            long retryAfter = status == 503 ? retryAfterMillis(metadata.retryAfter)
                    : status == 429 ? retryAfterMillis(response.header("Retry-After")) : 0;
            if (status != 200) return result(false, status, "HTTP_STATUS", retryAfter);
            ResponseBody responseBody = response.body();
            if (responseBody == null) return result(false, status, "INVALID_RESPONSE", 0);
            if (responseBody.contentLength() > RESPONSE_LIMIT) return result(false, status, "RESPONSE_TOO_LARGE", 0);
            byte[] bytes = readBounded(responseBody.byteStream());
            if (bytes == null) return result(false, status, "RESPONSE_TOO_LARGE", 0);
            return acknowledgement(status, bytes);
        } catch (InterruptedIOException e) {
            return result(false, status, "TIMEOUT", 0);
        } catch (IOException e) {
            return result(false, status, "IO_ERROR", 0);
        }
    }

    private static Result acknowledgement(int status, byte[] bytes) {
        try (JsonParser parser = JSON_FACTORY.createParser(bytes)) {
            if (parser.nextToken() != JsonToken.START_OBJECT) return result(false, status, "INVALID_RESPONSE", 0);
            boolean codeSeen = false;
            boolean accepted = false;
            int depth = 1;
            JsonToken token;
            // Stream unknown fields instead of building a recursive tree: even 16 KiB can
            // contain thousands of nesting levels and overflow a tree deserializer's stack.
            while ((token = parser.nextToken()) != null) {
                if (depth == 1 && token == JsonToken.FIELD_NAME && "code".equals(parser.getCurrentName())) {
                    if (parser.nextToken() != JsonToken.VALUE_NUMBER_INT) return result(false, status, "INVALID_RESPONSE", 0);
                    codeSeen = true;
                    accepted = parser.getBigIntegerValue().signum() == 0;
                    continue;
                }
                if (token == JsonToken.START_OBJECT || token == JsonToken.START_ARRAY) depth++;
                else if (token == JsonToken.END_OBJECT || token == JsonToken.END_ARRAY) depth--;
                if (depth == 0) {
                    if (!codeSeen || parser.nextToken() != null) return result(false, status, "INVALID_RESPONSE", 0);
                    return result(accepted, status, accepted ? "OK" : "RECEIVER_REJECTED", 0);
                }
            }
            return result(false, status, "INVALID_RESPONSE", 0);
        } catch (IOException e) {
            return result(false, status, "INVALID_RESPONSE", 0);
        }
    }

    /** Reads at most limit+1 bytes, including when Content-Length is absent or incorrect. */
    private static byte[] readBounded(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[2048];
        while (output.size() <= RESPONSE_LIMIT) {
            int size = input.read(buffer, 0, Math.min(buffer.length, RESPONSE_LIMIT + 1 - output.size()));
            if (size == -1) return output.toByteArray();
            output.write(buffer, 0, size);
        }
        return null;
    }

    private long retryAfterMillis(String value) {
        if (value == null) return 0;
        String trimmed = value.trim();
        if (trimmed.matches("[0-9]+")) {
            String significant = trimmed.replaceFirst("^0+", "");
            if (significant.isEmpty()) return 0;
            if (significant.length() > 3) return MAX_RETRY_AFTER_MILLIS;
            return Math.min(Long.parseLong(significant) * 1000, MAX_RETRY_AFTER_MILLIS);
        }
        try {
            long seconds = ZonedDateTime.parse(trimmed, DateTimeFormatter.RFC_1123_DATE_TIME)
                    .toInstant().getEpochSecond() - clock.instant().getEpochSecond();
            if (seconds <= 0) return 0;
            return seconds >= 300 ? MAX_RETRY_AFTER_MILLIS : seconds * 1000;
        } catch (DateTimeParseException e) { return 0; }
    }

    private static Result result(boolean success, int status, String outcome, long retryAfterMillis) {
        return new Result(success, status, outcome, retryAfterMillis);
    }

    private static final class RetryMetadata { private String retryAfter; }

    /** Only fixed outcomes and protocol metadata may be persisted; never response bodies or secrets. */
    public static final class Result {
        public final boolean success;
        public final int httpStatus;
        public final String outcome;
        public final long retryAfterMillis;
        public Result(boolean success, int httpStatus, String outcome, long retryAfterMillis) {
            this.success = success;
            this.httpStatus = httpStatus;
            this.outcome = outcome;
            this.retryAfterMillis = retryAfterMillis;
        }
    }
}
