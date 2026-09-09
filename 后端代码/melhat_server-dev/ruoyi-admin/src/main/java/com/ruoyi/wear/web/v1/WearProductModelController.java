package com.ruoyi.wear.web.v1;

import java.util.List;
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
import com.ruoyi.wear.device.ProductModelService;
import com.ruoyi.wear.device.dto.ProductModelDto;

@RestController
@RequestMapping("/api/v1/product-models")
public class WearProductModelController
{
    @Autowired
    private ProductModelService productModelService;

    @GetMapping
    public R<List<ProductModelDto>> list(@RequestParam(required = false) String typeCode)
    {
        return R.ok(productModelService.list(typeCode));
    }

    @GetMapping("/{id}")
    public R<ProductModelDto> detail(@PathVariable Long id)
    {
        return R.ok(productModelService.detail(id));
    }

    @PostMapping
    public R<ProductModelDto> create(@RequestBody ProductModelDto request)
    {
        return R.ok(productModelService.create(request));
    }

    @PutMapping("/{id}")
    public R<ProductModelDto> update(@PathVariable Long id, @RequestBody ProductModelDto request)
    {
        return R.ok(productModelService.update(id, request));
    }
}
