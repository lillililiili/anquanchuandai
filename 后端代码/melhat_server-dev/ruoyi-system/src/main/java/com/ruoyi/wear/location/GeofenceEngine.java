package com.ruoyi.wear.location;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.TimeZone;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.event.dto.IngestRequest;
import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.location.domain.WearGeoFence;
import com.ruoyi.wear.location.domain.WearGeoFencePerson;
import com.ruoyi.wear.location.domain.WearGeoFenceState;
import com.ruoyi.wear.location.mapper.WearGeoFenceMapper;
import com.ruoyi.wear.location.mapper.WearGeoFencePersonMapper;
import com.ruoyi.wear.location.mapper.WearGeoFenceStateMapper;

@Service
public class GeofenceEngine
{
    @Autowired
    private WearGeoFenceMapper fenceMapper;
    @Autowired
    private WearGeoFencePersonMapper fencePersonMapper;
    @Autowired
    private WearGeoFenceStateMapper stateMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private GeofenceEventWriter geofenceEventWriter;
    @Value("${melhat.telemetry.stale-after-seconds:180}")
    private int staleAfterSeconds;

    public void onHelmetSample(WearDevice device, Date occurred, BigDecimal lat, BigDecimal lng, String locationQuality)
    {
        if (device == null || device.getSiteId() == null || lat == null || lng == null)
        {
            return;
        }
        Date now = new Date();
        if (!GeofencePolicy.sampleEligible(locationQuality, occurred, now, staleAfterSeconds))
        {
            return;
        }
        WearAssignment assignment = assignmentMapper.findAtDeviceTime(device.getId(), occurred);
        if (assignment == null || assignment.getPersonId() == null)
        {
            return;
        }
        evaluate(device.getSiteId(), assignment.getPersonId(), device, occurred, lat, lng, locationQuality, now, false);
    }

    public int evaluate(Long siteId, Long personId, WearDevice device, Date occurred, BigDecimal lat, BigDecimal lng,
            String locationQuality, Date now, boolean demo)
    {
        int fired = 0;
        List<WearGeoFence> fences = fenceMapper.selectList(new LambdaQueryWrapper<WearGeoFence>()
                .eq(WearGeoFence::getSiteId, siteId).eq(WearGeoFence::getEnabled, 1));
        for (WearGeoFence fence : fences)
        {
            if (!applies(fence, personId) || !inTimeWindow(fence, occurred == null ? now : occurred))
            {
                continue;
            }
            List<double[]> ring = parseRing(fence.getPolygonJson());
            boolean inside = PointInPolygon.contains(lng.doubleValue(), lat.doubleValue(), ring);
            WearGeoFenceState state = stateMapper.selectOne(new LambdaQueryWrapper<WearGeoFenceState>()
                    .eq(WearGeoFenceState::getFenceId, fence.getId())
                    .eq(WearGeoFenceState::getPersonId, personId));
            if (state == null)
            {
                state = new WearGeoFenceState();
                state.setFenceId(fence.getId());
                state.setPersonId(personId);
                state.setInside(0);
                stateMapper.insert(state);
                state = stateMapper.selectOne(new LambdaQueryWrapper<WearGeoFenceState>()
                        .eq(WearGeoFenceState::getFenceId, fence.getId())
                        .eq(WearGeoFenceState::getPersonId, personId));
            }
            boolean wasInside = state.getInside() != null && state.getInside().intValue() == 1;
            int debounce = fence.getDebounceSeconds() == null ? 60 : fence.getDebounceSeconds().intValue();
            Integer candidate = state.getCandidateInside();
            if (candidate == null || candidate.intValue() != (inside ? 1 : 0))
            {
                state.setCandidateInside(inside ? 1 : 0);
                state.setSince(now);
                state.setLastEvalAt(now);
                stateMapper.updateById(state);
                if (debounce > 0)
                {
                    continue;
                }
            }
            if (!GeofencePolicy.debounceReady(state.getSince(), now, debounce))
            {
                state.setLastEvalAt(now);
                stateMapper.updateById(state);
                continue;
            }
            String action = GeofencePolicy.transition(wasInside, inside);
            state.setInside(inside ? 1 : 0);
            state.setCandidateInside(inside ? 1 : 0);
            state.setSince(now);
            state.setLastEvalAt(now);
            stateMapper.updateById(state);
            if (action == null)
            {
                continue;
            }
            if (GeofencePolicy.ENTER.equals(action) && (fence.getEnterEnabled() == null || fence.getEnterEnabled().intValue() == 0))
            {
                continue;
            }
            if (GeofencePolicy.LEAVE.equals(action) && (fence.getLeaveEnabled() == null || fence.getLeaveEnabled().intValue() == 0))
            {
                continue;
            }
            fire(fence, personId, device, occurred, lat, lng, locationQuality, action,
                    demo || (fence.getDemo() != null && fence.getDemo().intValue() == 1), debounce);
            fired++;
        }
        return fired;
    }

    private void fire(WearGeoFence fence, Long personId, WearDevice device, Date occurred, BigDecimal lat, BigDecimal lng,
            String quality, String action, boolean demo, int debounce)
    {
        long windowMs = debounce <= 0 ? 1000L : debounce * 1000L;
        long bucket = occurred.getTime() / windowMs;
        IngestRequest ingest = new IngestRequest();
        ingest.setSource("geofence");
        ingest.setSourceEventId(fence.getId() + "|" + personId + "|" + action + "|" + fence.getRuleVersion() + "|" + bucket);
        ingest.setType("geofence");
        ingest.setSiteId(String.valueOf(fence.getSiteId()));
        ingest.setPersonId(String.valueOf(personId));
        if (device != null)
        {
            ingest.setDeviceId(String.valueOf(device.getId()));
        }
        ingest.setOccurredAt(occurred);
        ingest.setLat(lat);
        ingest.setLng(lng);
        ingest.setLocationQuality(quality == null ? TelemetryFreshness.OK : quality);
        ingest.setDemo(demo);
        ingest.setActor("geofence");
        ingest.setFenceId(fence.getId());
        ingest.setFenceAction(action);
        ingest.setRuleVersion("fence-" + fence.getRuleVersion());
        try
        {
            geofenceEventWriter.write(ingest);
        }
        catch (Exception ignored)
        {
        }
    }

    private boolean applies(WearGeoFence fence, Long personId)
    {
        if (!"persons".equals(fence.getApplyMode()))
        {
            return true;
        }
        return fencePersonMapper.selectCount(new LambdaQueryWrapper<WearGeoFencePerson>()
                .eq(WearGeoFencePerson::getFenceId, fence.getId())
                .eq(WearGeoFencePerson::getPersonId, personId)) > 0;
    }

    private boolean inTimeWindow(WearGeoFence fence, Date at)
    {
        if (fence.getTimeStart() == null || fence.getTimeEnd() == null
                || fence.getTimeStart().isEmpty() || fence.getTimeEnd().isEmpty())
        {
            return true;
        }
        Calendar cal = Calendar.getInstance(TimeZone.getTimeZone("GMT+8"));
        cal.setTime(at);
        String hm = String.format("%02d:%02d", cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE));
        return hm.compareTo(fence.getTimeStart()) >= 0 && hm.compareTo(fence.getTimeEnd()) <= 0;
    }

    static List<double[]> parseRing(String json)
    {
        List<double[]> ring = new ArrayList<double[]>();
        if (json == null || json.trim().isEmpty())
        {
            return ring;
        }
        JSONArray arr = JSON.parseArray(json);
        if (arr == null)
        {
            return ring;
        }
        for (int i = 0; i < arr.size(); i++)
        {
            JSONObject obj = arr.getJSONObject(i);
            if (obj == null)
            {
                continue;
            }
            Double lng = obj.getDouble("lng");
            Double lat = obj.getDouble("lat");
            if (lng == null)
            {
                lng = obj.getDouble("longitude");
            }
            if (lat == null)
            {
                lat = obj.getDouble("latitude");
            }
            if (lng != null && lat != null)
            {
                ring.add(new double[] { lng.doubleValue(), lat.doubleValue() });
            }
        }
        return ring;
    }
}
