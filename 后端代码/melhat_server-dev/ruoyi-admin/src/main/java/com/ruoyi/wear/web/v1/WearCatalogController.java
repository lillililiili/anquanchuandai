package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.org.OrgCatalogService;
import com.ruoyi.wear.space.SpaceService;

@RestController
@RequestMapping("/api/v1")
public class WearCatalogController
{
    @Autowired
    private OrgCatalogService orgCatalogService;
    @Autowired
    private SpaceService spaceService;

    @GetMapping("/teams")
    public R<List<Map<String, String>>> teams()
    {
        return R.ok(orgCatalogService.listTeams());
    }

    @PostMapping("/teams")
    public R<Map<String, String>> createTeam(@RequestBody Map<String, String> body)
    {
        return R.ok(orgCatalogService.createTeam(body.get("name"), body.get("siteId")));
    }

    @PutMapping("/teams/{id}")
    public R<Map<String, String>> updateTeam(@PathVariable Long id, @RequestBody Map<String, String> body)
    {
        return R.ok(orgCatalogService.updateTeam(id, body.get("name"), body.get("status")));
    }

    @GetMapping("/contractors")
    public R<List<Map<String, String>>> contractors()
    {
        return R.ok(orgCatalogService.listContractors());
    }

    @PostMapping("/contractors")
    public R<Map<String, String>> createContractor(@RequestBody Map<String, String> body)
    {
        return R.ok(orgCatalogService.createContractor(body.get("name")));
    }

    @PutMapping("/contractors/{id}")
    public R<Map<String, String>> updateContractor(@PathVariable Long id, @RequestBody Map<String, String> body)
    {
        return R.ok(orgCatalogService.updateContractor(id, body.get("name"), body.get("status")));
    }

    @GetMapping("/spaces")
    public R<List<Map<String, String>>> spaces(@RequestParam(required = false) String siteId)
    {
        return R.ok(spaceService.list(siteId));
    }

    @PostMapping("/spaces")
    public R<Map<String, String>> createSpace(@RequestBody Map<String, String> body)
    {
        return R.ok(spaceService.create(body.get("siteId"), body.get("parentId"), body.get("spaceType"), body.get("name")));
    }

    @PutMapping("/spaces/{id}")
    public R<Map<String, String>> updateSpace(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        String name = body.get("name") == null ? null : String.valueOf(body.get("name"));
        Integer version = body.get("version") == null ? null : Integer.valueOf(String.valueOf(body.get("version")));
        return R.ok(spaceService.update(id, name, version));
    }
}
