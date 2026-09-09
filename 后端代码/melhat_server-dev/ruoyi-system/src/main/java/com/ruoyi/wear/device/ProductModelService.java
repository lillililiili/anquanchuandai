package com.ruoyi.wear.device;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.dto.CapabilityDto;
import com.ruoyi.wear.device.dto.ProductModelDto;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;

@Service
public class ProductModelService
{
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private SiteAccessService siteAccessService;

    public List<ProductModelDto> list(String typeCode)
    {
        siteAccessService.requireLogin();
        LambdaQueryWrapper<WearProductModel> query = new LambdaQueryWrapper<WearProductModel>()
                .eq(WearProductModel::getStatus, "0")
                .orderByAsc(WearProductModel::getId);
        if (StringUtils.isNotEmpty(typeCode))
        {
            query.eq(WearProductModel::getTypeCode, typeCode);
        }
        List<ProductModelDto> result = new ArrayList<ProductModelDto>();
        for (WearProductModel model : modelMapper.selectList(query))
        {
            result.add(toDto(model));
        }
        return result;
    }

    public ProductModelDto detail(Long id)
    {
        siteAccessService.requireLogin();
        WearProductModel model = modelMapper.selectById(id);
        if (model == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        return toDto(model);
    }

    public ProductModelDto create(ProductModelDto request)
    {
        siteAccessService.assertCanWriteDevice();
        validateWrite(request, true);
        if (modelMapper.selectCount(new LambdaQueryWrapper<WearProductModel>()
                .eq(WearProductModel::getModelCode, request.getModelCode().trim())) > 0)
        {
            throw new ServiceException("型号编码已存在", HttpStatus.CONFLICT);
        }
        WearProductModel model = new WearProductModel();
        apply(model, request);
        model.setStatus("0");
        model.setVersion(1);
        model.setDelFlag("0");
        model.setCreateBy(SecurityUtils.getUsername());
        model.setCreateTime(new Date());
        modelMapper.insert(model);
        return toDto(model);
    }

    public ProductModelDto update(Long id, ProductModelDto request)
    {
        siteAccessService.assertCanWriteDevice();
        WearProductModel model = modelMapper.selectById(id);
        if (model == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        if (request.getVersion() == null || !request.getVersion().equals(model.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        validateWrite(request, false);
        if (StringUtils.isNotEmpty(request.getModelCode()) && !request.getModelCode().equals(model.getModelCode()))
        {
            if (modelMapper.selectCount(new LambdaQueryWrapper<WearProductModel>()
                    .eq(WearProductModel::getModelCode, request.getModelCode().trim())
                    .ne(WearProductModel::getId, id)) > 0)
            {
                throw new ServiceException("型号编码已存在", HttpStatus.CONFLICT);
            }
        }
        apply(model, request);
        model.setVersion(model.getVersion() + 1);
        model.setUpdateBy(SecurityUtils.getUsername());
        model.setUpdateTime(new Date());
        modelMapper.updateById(model);
        return toDto(model);
    }

    private void validateWrite(ProductModelDto request, boolean creating)
    {
        if (request == null)
        {
            throw new ServiceException("型号不能为空", HttpStatus.BAD_REQUEST);
        }
        if (creating && (StringUtils.isEmpty(request.getModelCode()) || StringUtils.isEmpty(request.getName())
                || StringUtils.isEmpty(request.getTypeCode()) || StringUtils.isEmpty(request.getManufacturerCode())))
        {
            throw new ServiceException("型号编码、名称、类型和厂商不能为空", HttpStatus.BAD_REQUEST);
        }
        if (StringUtils.isNotEmpty(request.getTypeCode())
                && !"helmet".equals(request.getTypeCode()) && !"belt".equals(request.getTypeCode()))
        {
            throw new ServiceException("产品类型无效", HttpStatus.BAD_REQUEST);
        }
    }

    private void apply(WearProductModel model, ProductModelDto request)
    {
        if (StringUtils.isNotEmpty(request.getTypeCode()))
        {
            model.setTypeCode(request.getTypeCode().trim());
        }
        if (StringUtils.isNotEmpty(request.getModelCode()))
        {
            model.setModelCode(request.getModelCode().trim());
        }
        if (StringUtils.isNotEmpty(request.getManufacturerCode()))
        {
            model.setManufacturerCode(request.getManufacturerCode().trim());
        }
        if (StringUtils.isNotEmpty(request.getName()))
        {
            model.setName(request.getName().trim());
        }
        if (request.getProtocolVersion() != null)
        {
            model.setProtocolVersion(request.getProtocolVersion());
        }
        if (request.getCapabilities() != null)
        {
            CapabilityDto caps = request.getCapabilities();
            if (StringUtils.isEmpty(caps.getProtocolVersion()) && StringUtils.isNotEmpty(request.getProtocolVersion()))
            {
                caps.setProtocolVersion(request.getProtocolVersion());
            }
            model.setCapabilities(DeviceCapability.toJson(caps));
        }
        else if (creatingNeedsCaps(model))
        {
            CapabilityDto empty = new CapabilityDto();
            empty.setProtocolVersion(request.getProtocolVersion());
            model.setCapabilities(DeviceCapability.toJson(empty));
        }
    }

    private boolean creatingNeedsCaps(WearProductModel model)
    {
        return StringUtils.isEmpty(model.getCapabilities());
    }

    public ProductModelDto toDto(WearProductModel model)
    {
        ProductModelDto dto = new ProductModelDto();
        dto.setId(String.valueOf(model.getId()));
        dto.setTypeCode(model.getTypeCode());
        dto.setModelCode(model.getModelCode());
        dto.setManufacturerCode(model.getManufacturerCode());
        dto.setName(model.getName());
        dto.setProtocolVersion(model.getProtocolVersion());
        dto.setCapabilities(DeviceCapability.parse(model.getCapabilities()));
        dto.setStatus(model.getStatus());
        dto.setVersion(model.getVersion());
        return dto;
    }
}
