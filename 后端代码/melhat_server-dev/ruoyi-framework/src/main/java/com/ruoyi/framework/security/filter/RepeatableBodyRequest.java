package com.ruoyi.framework.security.filter;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import javax.servlet.ReadListener;
import javax.servlet.ServletInputStream;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletRequestWrapper;
import org.springframework.util.StreamUtils;

public class RepeatableBodyRequest extends HttpServletRequestWrapper
{
    private final byte[] body;

    public RepeatableBodyRequest(HttpServletRequest request) throws IOException
    {
        super(request);
        InputStream in = request.getInputStream();
        this.body = in == null ? new byte[0] : StreamUtils.copyToByteArray(in);
    }

    public byte[] getBody()
    {
        return body;
    }

    @Override
    public ServletInputStream getInputStream()
    {
        final ByteArrayInputStream source = new ByteArrayInputStream(body);
        return new ServletInputStream()
        {
            @Override
            public int read()
            {
                return source.read();
            }

            @Override
            public boolean isFinished()
            {
                return source.available() == 0;
            }

            @Override
            public boolean isReady()
            {
                return true;
            }

            @Override
            public void setReadListener(ReadListener listener)
            {
            }
        };
    }

    @Override
    public BufferedReader getReader()
    {
        return new BufferedReader(new InputStreamReader(getInputStream(), StandardCharsets.UTF_8));
    }
}
