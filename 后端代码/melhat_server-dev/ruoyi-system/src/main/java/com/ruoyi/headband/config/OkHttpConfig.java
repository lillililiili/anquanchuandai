package com.ruoyi.headband.config;

import okhttp3.ConnectionPool;
import okhttp3.OkHttpClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.concurrent.TimeUnit;

@Configuration
public class OkHttpConfig {

    @Bean
    public OkHttpClient okHttpClient() {
        // 创建一个默认的信任管理器，信任所有证书（生产环境请按需配置）
        X509TrustManager trustManager = new X509TrustManager() {
            @Override
            public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {
            }

            @Override
            public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
            }

            @Override
            public X509Certificate[] getAcceptedIssuers() {
                return new X509Certificate[0];
            }
        };

       /* SSLContext sslContext = null;
        try {
            sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, new TrustManager[]{trustManager}, new java.security.SecureRandom());
        } catch (NoSuchAlgorithmException | KeyManagementException e) {
            e.printStackTrace();
        }
        SSLSocketFactory sslSocketFactory = sslContext != null ? sslContext.getSocketFactory() : null;
        */
        return new OkHttpClient.Builder()
                // 连接超时时间
                .connectTimeout(10, TimeUnit.SECONDS)
                // 读取超时时间
                .readTimeout(30, TimeUnit.SECONDS)
                // 写入超时时间
                .writeTimeout(30, TimeUnit.SECONDS)
                // 连接池配置：最大空闲连接数5，存活时间5分钟
                .connectionPool(new ConnectionPool(5, 5, TimeUnit.MINUTES))
                // 失败重试：是否自动重试
                .retryOnConnectionFailure(true)
                // 设置连接失败后是否尝试其他IP（多IP服务有用）
                .followRedirects(true)          // 是否跟随重定向
                .followSslRedirects(true)       // 是否跟随SSL重定向
                // 配置SSL套接字工厂和信任管理器（跳过证书验证示例，生产请使用实际证书）
//                .sslSocketFactory(sslSocketFactory, trustManager)
                // 主机名验证器（此处设为不验证主机名，生产环境请慎重）
                .hostnameVerifier((hostname, session) -> true)
                .build();
    }


}