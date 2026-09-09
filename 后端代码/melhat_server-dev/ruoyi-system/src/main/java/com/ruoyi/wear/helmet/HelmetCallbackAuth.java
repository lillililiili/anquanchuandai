package com.ruoyi.wear.helmet;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class HelmetCallbackAuth
{
    public static final String TOKEN_HEADER = "X-Melhat-Callback-Token";
    public static final String TIMESTAMP_HEADER = "X-Melhat-Timestamp";
    public static final String NONCE_HEADER = "X-Melhat-Nonce";
    public static final String SIGNATURE_HEADER = "X-Melhat-Signature";

    private HelmetCallbackAuth()
    {
    }

    public static boolean tokenMatches(String expected, String provided)
    {
        if (expected == null || expected.isEmpty() || provided == null || provided.isEmpty())
        {
            return false;
        }
        byte[] left = expected.getBytes(StandardCharsets.UTF_8);
        byte[] right = provided.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(left, right);
    }

    public static String hmacHex(String secret, String timestamp, String nonce, byte[] body)
    {
        if (secret == null)
        {
            return null;
        }
        try
        {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            String prefix = nullToEmpty(timestamp) + "\n" + nullToEmpty(nonce) + "\n";
            mac.update(prefix.getBytes(StandardCharsets.UTF_8));
            if (body != null)
            {
                mac.update(body);
            }
            byte[] raw = mac.doFinal();
            StringBuilder hex = new StringBuilder(raw.length * 2);
            for (int i = 0; i < raw.length; i++)
            {
                hex.append(String.format("%02x", raw[i] & 0xff));
            }
            return hex.toString();
        }
        catch (Exception ex)
        {
            throw new IllegalStateException("HMAC failed", ex);
        }
    }

    public static String verifyHmac(String secret, String timestamp, String nonce, byte[] body, String signature,
            long nowEpochSeconds, int skewSeconds)
    {
        if (secret == null || secret.isEmpty())
        {
            return null;
        }
        if (timestamp == null || nonce == null || nonce.isEmpty() || signature == null || signature.isEmpty())
        {
            return "missing hmac headers";
        }
        long ts;
        try
        {
            ts = Long.parseLong(timestamp.trim());
        }
        catch (NumberFormatException ex)
        {
            return "bad timestamp";
        }
        int skew = skewSeconds < 1 ? 300 : skewSeconds;
        if (Math.abs(nowEpochSeconds - ts) > skew)
        {
            return "timestamp skew";
        }
        String expected = hmacHex(secret, timestamp, nonce, body);
        byte[] left = expected.getBytes(StandardCharsets.UTF_8);
        byte[] right = signature.trim().toLowerCase().getBytes(StandardCharsets.UTF_8);
        if (!MessageDigest.isEqual(left, right))
        {
            return "bad signature";
        }
        return null;
    }

    private static String nullToEmpty(String value)
    {
        return value == null ? "" : value;
    }
}
