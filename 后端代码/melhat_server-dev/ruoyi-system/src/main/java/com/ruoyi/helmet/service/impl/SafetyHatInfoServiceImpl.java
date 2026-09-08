package com.ruoyi.helmet.service.impl;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.additional.query.impl.LambdaQueryChainWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.bean.BeanUtils;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.service.IGroupInfoService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.ruoyi.helmet.vo.SafetyHatListVO;
import com.ruoyi.helmet.vo.SafetyHatQueryVO;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

/**
 * <p>
 * 安全帽信息表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class SafetyHatInfoServiceImpl extends ServiceImpl<SafetyHatInfoMapper, SafetyHatInfo> implements ISafetyHatInfoService {

    @Autowired
    private IGroupInfoService groupInfoService;
    @Autowired
    private HeadbandService headbandService;
    @Autowired
    private ISafetyHatLocationRecordService safetyHatLocationRecordService;
    @Value("${melhat.demo-mode:false}")
    private boolean demoMode;

    @Override
    public Page<SafetyHatListVO> pageQuery(SafetyHatQueryVO queryVO, int current, int size) {
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();

        if (StringUtils.hasText(queryVO.getHatNumber())) {
            wrapper.like(SafetyHatInfo::getHatNumber, queryVO.getHatNumber());
        }
        if (StringUtils.hasText(queryVO.getBindUserName())) {
            wrapper.like(SafetyHatInfo::getBindUserName, queryVO.getBindUserName());
        }
        if (StringUtils.hasText(queryVO.getBindGroup()) && !"全部".equals(queryVO.getBindGroup())) {
            wrapper.eq(SafetyHatInfo::getBindGroup, queryVO.getBindGroup());
        }
        if (StringUtils.hasText(queryVO.getStatus()) && !"全部".equals(queryVO.getStatus())) {
            wrapper.eq(SafetyHatInfo::getStatus, queryVO.getStatus());
        }
        if (queryVO.getStartTime() != null) {
            wrapper.ge(SafetyHatInfo::getBindTime, queryVO.getStartTime());
        }
        if (queryVO.getEndTime() != null) {
            wrapper.le(SafetyHatInfo::getBindTime, queryVO.getEndTime());
        }

        // 默认不查已删除的数据
        wrapper.eq(SafetyHatInfo::getDelFlag, '0');

        IPage<SafetyHatInfo> page1 = this.page(new Page<>(current, size), wrapper);
        //同步状态
        IPage<SafetyHatInfo> page = getStatusInfo(page1);
        // 转换为 VO
        List<SafetyHatListVO> voList = page.getRecords().stream()
                .map(this::convertToVO)
                .collect(Collectors.toList());

        Page<SafetyHatListVO> resultPage = new Page<>();
        BeanUtils.copyProperties(page, resultPage);
        resultPage.setRecords(voList);

        return resultPage;
    }

    IPage<SafetyHatInfo> getStatusInfo(IPage<SafetyHatInfo> page) {
        if (demoMode) {
            return page;
        }
        List<String> hatNumbers = page.getRecords().stream()
                .map(SafetyHatInfo::getHatNumber)
                .collect(Collectors.toList());

        Map<String, Object> param = new HashMap<>();
        param.put("helmetSnList", hatNumbers);
        param.put("statusOnline", "");
        try {
            List<HeadbandVO> headBandList = headbandService.getHeadBandList(param);
            if (!CollectionUtils.isEmpty(headBandList)) {
                page.getRecords().forEach(hat -> {
                    HeadbandVO headbandVO = headBandList.stream().filter(g -> g.getHelmetSn().equals(hat.getHatNumber())).findFirst().orElse(null);
                    if (headbandVO != null) {
                        hat.setStatus(headbandVO.getOnline());
                        hat.setUid(headbandVO.getUid_device());
                    }
                });
            }
        } catch (Exception e) {
            log.error("同步安全帽在线状态异常:",e);
            return page;
        }
        return page;

    }

    @Override
    public List<SafetyHatListVO> listAll() {
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(SafetyHatInfo::getDelFlag, '0');
        List<SafetyHatInfo> list = this.list(wrapper);
        return list.stream().map(this::convertToVO).collect(Collectors.toList());
    }

    @Override
    public SafetyHatInfo getById(Long id) {
        return super.getById(id);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean saveOrUpdate(SafetyHatInfo safetyHat) {
        // 检查 hatNumber 是否重复
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(SafetyHatInfo::getHatNumber, safetyHat.getHatNumber());
        wrapper.eq(SafetyHatInfo::getDelFlag, "0"); // 只检查未删除的记录

        if (safetyHat.getId() != null) {
            // 修改时，排除当前记录
            wrapper.ne(SafetyHatInfo::getId, safetyHat.getId());
        }

        if (this.count(wrapper) > 0) {
            throw new ServiceException("安全帽编号已存在");
        }

        Date now = new Date();
        Long newGroupId = safetyHat.getBindGroupId();
        if (safetyHat.getId() == null) {
            safetyHat.setCreateTime(now);
            safetyHat.setCreateBy(SecurityUtils.getUsername()); // 可从上下文获取当前用户
            safetyHat.setDelFlag("0");
            safetyHat.setStatus("1"); // 默认正常
            if (null != safetyHat.getBindUserId()) {
                SafetyHatInfo hat = getHatByUserId(safetyHat.getBindUserId());
                if(hat != null){
                    throw new ServiceException("该用户已绑定安全帽:" + hat.getHatNumber());
                }
                safetyHat.setBindTime(now);
            }

            if (null != newGroupId) {
                groupInfoService.increaseCountById(newGroupId);
            }
            return super.saveOrUpdate(safetyHat);
        } else {
            SafetyHatInfo oldInfo = getById(safetyHat.getId());
            if (null != safetyHat.getBindUserId()) {
                SafetyHatInfo bindhat = getHatByUserId(safetyHat.getBindUserId());
                if(bindhat != null && !bindhat.getHatNumber().equals(safetyHat.getHatNumber())){
                    throw new ServiceException("该用户已绑定安全帽:" + bindhat.getHatNumber());
                }
                // 比较数据库中绑定用户的id和前端传递的绑定用户id
                if (oldInfo.getBindUserId() == null || !oldInfo.getBindUserId().equals(safetyHat.getBindUserId())) {
                    // 绑定用户变化，更新绑定时间
                    safetyHat.setBindTime(now);
                }
            }
            safetyHat.setUpdateTime(now);
            safetyHat.setUpdateBy(SecurityUtils.getUsername());

            Long oldGroupId = oldInfo != null ? oldInfo.getBindGroupId() : null;
            if (oldGroupId != null && !oldGroupId.equals(newGroupId)) {
                // 分组变化，旧组数量-1，新组数量+1
                groupInfoService.decreaseCountById(oldGroupId);
                groupInfoService.increaseCountById(newGroupId);
            } else if (oldGroupId == null) {
                // 原本无分组，新增分组，新组数量+1
                groupInfoService.increaseCountById(newGroupId);
            }
            int i = getBaseMapper().updateSafetyHatInfo(safetyHat);
            return i>0;
        }
    }

    @Override
    public boolean deleteById(Long id) {
        SafetyHatInfo safetyHat = this.getById(id);
        if (safetyHat != null) {
            boolean update = this.update(null, new LambdaUpdateWrapper<SafetyHatInfo>()
                    .eq(SafetyHatInfo::getId, id)
                    .set(SafetyHatInfo::getDelFlag, "2")
                    .set(SafetyHatInfo::getUpdateTime, new Date())
                    .set(SafetyHatInfo::getUpdateBy, SecurityUtils.getUsername()));
            return update;
        }
        return false;
    }

    @Override
    public boolean batchDelete(List<Long> ids) {
        for (Long id : ids) {
            deleteById(id);
        }
        return true;
    }

    @Override
    public boolean updateStatus(Long id, String status) {
        SafetyHatInfo safetyHat = this.getById(id);
        if (safetyHat != null) {
            safetyHat.setStatus(status);
            safetyHat.setUpdateTime(new Date());
            safetyHat.setUpdateBy(SecurityUtils.getUsername());
            return this.updateById(safetyHat);
        }
        return false;
    }

    @Override
    public SafetyHatListVO getByHatNumber(String hatNumber) {
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(SafetyHatInfo::getHatNumber, hatNumber);
        SafetyHatInfo safetyHatInfo = this.getOne(wrapper);
        if (safetyHatInfo == null) {
            throw new ServiceException("未获取到帽子");
        }
        SafetyHatListVO safetyHatListVO = convertToVO(safetyHatInfo);
        SafetyHatLocationRecord location = safetyHatLocationRecordService.lambdaQuery()
                .eq(SafetyHatLocationRecord::getHatNumber, hatNumber)
                .orderByDesc(SafetyHatLocationRecord::getTimestamp)
                .last("limit 1").one();
        if (location != null) {
            safetyHatListVO.setLongitude(location.getLng());
            safetyHatListVO.setLatitude(location.getLat());
        }
        return safetyHatListVO;
    }

    private SafetyHatListVO convertToVO(SafetyHatInfo entity) {
        SafetyHatListVO vo = new SafetyHatListVO();
        BeanUtils.copyProperties(entity, vo);

        // 状态翻译
        if ("1".equals(entity.getStatus())) {
            vo.setStatusText("正常使用");
        } else if ("0".equals(entity.getStatus())) {
            vo.setStatusText("已离线");
        }

        // 格式化电量、存储等进度条颜色（前端可能需要）
        vo.setElectricityColor(getColorByPercent(entity.getElectricityUsage()));
        vo.setStorageColor(getColorByPercent(entity.getStorageUsage()));

        return vo;
    }

    private String getColorByPercent(BigDecimal percent) {
        if (percent == null) return "#ccc";
        double p = percent.doubleValue();
        if (p >= 80) return "#52c41a"; // 绿色
        else if (p >= 40) return "#faad14"; // 黄色
        else return "#f5222d"; // 红色
    }

    @Override
    public List<SafetyHatInfo> getHatNumbersByGroupNumber(Long groupId) {
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(SafetyHatInfo::getBindGroupId, groupId);
        // 可根据使用需求只查有效的、未解绑的安全帽
        wrapper.eq(SafetyHatInfo::getDelFlag, "0");
        List<SafetyHatInfo> list = this.list(wrapper);
        return list;
    }
    @Override
    public SafetyHatInfo getHatByUserId(Long userId) {
        LambdaQueryWrapper<SafetyHatInfo> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(SafetyHatInfo::getBindUserId, userId);
        // 可根据使用需求只查有效的、未解绑的安全帽
        wrapper.eq(SafetyHatInfo::getDelFlag, "0");
        List<SafetyHatInfo> list = this.list(wrapper);
        if(!CollectionUtils.isEmpty(list)){
           return list.get(0);
        }
        return null;
    }

}
