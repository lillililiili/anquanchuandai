package com.ruoyi.common.utils.file;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;

/**
 * 代理下载的最小安全边界：协议、解析地址、重定向、超时和大小。
 * 完整对象存储签发在后续阶段。
 */
public class SafeRemoteFileFetcher
{
    public static final int DEFAULT_CONNECT_TIMEOUT_MS = 5000;
    public static final int DEFAULT_READ_TIMEOUT_MS = 15000;
    public static final int DEFAULT_MAX_BYTES = 20 * 1024 * 1024;
    public static final int DEFAULT_MAX_REDIRECTS = 3;

    private final int connectTimeoutMs;
    private final int readTimeoutMs;
    private final int maxBytes;
    private final int maxRedirects;
    private final boolean allowPrivateNetwork;

    public SafeRemoteFileFetcher(int connectTimeoutMs, int readTimeoutMs, int maxBytes,
                                 int maxRedirects, boolean allowPrivateNetwork)
    {
        this.connectTimeoutMs = connectTimeoutMs;
        this.readTimeoutMs = readTimeoutMs;
        this.maxBytes = maxBytes;
        this.maxRedirects = maxRedirects;
        this.allowPrivateNetwork = allowPrivateNetwork;
    }

    public static SafeRemoteFileFetcher defaults(boolean allowPrivateNetwork)
    {
        return new SafeRemoteFileFetcher(DEFAULT_CONNECT_TIMEOUT_MS, DEFAULT_READ_TIMEOUT_MS,
                DEFAULT_MAX_BYTES, DEFAULT_MAX_REDIRECTS, allowPrivateNetwork);
    }

    public byte[] fetch(String rawUrl)
    {
        URI uri = validate(rawUrl);
        try
        {
            return fetch(uri, 0);
        }
        catch (IOException ex)
        {
            throw new ServiceException("文件下载失败");
        }
    }

    public URI validate(String rawUrl)
    {
        if (StringUtils.isEmpty(rawUrl))
        {
            throw new ServiceException("文件地址为空");
        }
        URI uri;
        try
        {
            uri = URI.create(rawUrl.trim());
        }
        catch (IllegalArgumentException ex)
        {
            throw new ServiceException("文件地址无效");
        }
        assertAllowed(uri);
        return uri;
    }

    public boolean isForbiddenAddress(InetAddress address)
    {
        if (address == null)
        {
            return true;
        }
        if (address.isAnyLocalAddress() || address.isMulticastAddress() || address.isLinkLocalAddress())
        {
            return true;
        }
        if (allowPrivateNetwork)
        {
            return false;
        }
        return address.isLoopbackAddress() || address.isSiteLocalAddress();
    }

    private byte[] fetch(URI uri, int redirectCount) throws IOException
    {
        if (redirectCount > maxRedirects)
        {
            throw new ServiceException("文件下载重定向次数过多");
        }
        assertAllowed(uri);
        HttpURLConnection connection = (HttpURLConnection) uri.toURL().openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestMethod("GET");
        int status = connection.getResponseCode();
        if (status >= 300 && status < 400)
        {
            String location = connection.getHeaderField("Location");
            connection.disconnect();
            if (StringUtils.isEmpty(location))
            {
                throw new ServiceException("文件下载重定向缺少地址");
            }
            URI next = uri.resolve(location);
            return fetch(next, redirectCount + 1);
        }
        if (status != HttpURLConnection.HTTP_OK)
        {
            connection.disconnect();
            throw new ServiceException("文件下载失败");
        }
        long contentLength = connection.getContentLengthLong();
        if (contentLength > maxBytes)
        {
            connection.disconnect();
            throw new ServiceException("文件超过允许的下载大小");
        }
        try (InputStream in = connection.getInputStream();
             ByteArrayOutputStream out = new ByteArrayOutputStream())
        {
            byte[] buffer = new byte[8192];
            int total = 0;
            int read;
            while ((read = in.read(buffer)) != -1)
            {
                total += read;
                if (total > maxBytes)
                {
                    throw new ServiceException("文件超过允许的下载大小");
                }
                out.write(buffer, 0, read);
            }
            return out.toByteArray();
        }
        finally
        {
            connection.disconnect();
        }
    }

    private void assertAllowed(URI uri)
    {
        String scheme = uri.getScheme();
        if (scheme == null
                || (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)))
        {
            throw new ServiceException("仅允许 http/https 下载");
        }
        String host = uri.getHost();
        if (StringUtils.isEmpty(host))
        {
            throw new ServiceException("文件地址缺少主机");
        }
        InetAddress[] addresses;
        try
        {
            addresses = InetAddress.getAllByName(host);
        }
        catch (UnknownHostException ex)
        {
            throw new ServiceException("无法解析文件地址");
        }
        if (addresses == null || addresses.length == 0)
        {
            throw new ServiceException("无法解析文件地址");
        }
        for (InetAddress address : addresses)
        {
            if (isForbiddenAddress(address))
            {
                throw new ServiceException("不允许下载该目标地址");
            }
        }
    }
}
