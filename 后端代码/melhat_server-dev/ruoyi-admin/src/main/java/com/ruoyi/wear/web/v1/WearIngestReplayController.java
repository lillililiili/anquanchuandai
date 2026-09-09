package com.ruoyi.wear.web.v1;

import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.helmet.HelmetAdapter;

@Profile("!prod")
@ConditionalOnProperty(name = "melhat.demo-mode", havingValue = "true")
@RestController
@RequestMapping("/api/v1/ingest")
public class WearIngestReplayController
{
    @Autowired
    private HelmetAdapter helmetAdapter;
    @Autowired
    private SiteAccessService siteAccessService;

    @PostMapping("/replay")
    public R<ResponseVO> replay(@RequestBody Map<String, Object> body)
    {
        siteAccessService.assertCanWriteDevice();
        if (body == null || StringUtils.isEmpty(str(body.get("path"))) || !(body.get("payload") instanceof Map))
        {
            throw new ServiceException("path 与 payload 不能为空", HttpStatus.BAD_REQUEST);
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) body.get("payload");
        return R.ok(helmetAdapter.replay(str(body.get("path")), payload));
    }

    private String str(Object value)
    {
        return value == null ? null : String.valueOf(value);
    }
}
