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
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.person.PersonService;
import com.ruoyi.wear.person.dto.PersonDto;
import com.ruoyi.wear.person.dto.PersonWriteRequest;

@RestController
@RequestMapping("/api/v1/people")
public class WearPeopleController
{
    @Autowired
    private PersonService personService;

    @GetMapping
    public R<WearPage<PersonDto>> page(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String name,
            @RequestParam(required = false) String personCode,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String teamId,
            @RequestParam(required = false) String contractorId)
    {
        return R.ok(personService.page(current, size, name, personCode, status, teamId, contractorId));
    }

    @GetMapping("/options")
    public R<List<PersonDto>> options(@RequestParam(required = false) String name)
    {
        return R.ok(personService.options(name));
    }

    @GetMapping("/{id}")
    public R<PersonDto> detail(@PathVariable Long id)
    {
        return R.ok(personService.detail(id));
    }

    @PostMapping
    public R<PersonDto> create(@RequestBody PersonWriteRequest request)
    {
        return R.ok(personService.create(request));
    }

    @PutMapping("/{id}")
    public R<PersonDto> update(@PathVariable Long id, @RequestBody PersonWriteRequest request)
    {
        return R.ok(personService.update(id, request));
    }

    @PutMapping("/{id}/status")
    public R<PersonDto> changeStatus(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        String status = body.get("status") == null ? null : String.valueOf(body.get("status"));
        Integer version = body.get("version") == null ? null : Integer.valueOf(String.valueOf(body.get("version")));
        return R.ok(personService.changeStatus(id, status, version));
    }
}
