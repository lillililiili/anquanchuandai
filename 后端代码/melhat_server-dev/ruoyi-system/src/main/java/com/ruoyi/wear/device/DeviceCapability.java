package com.ruoyi.wear.device;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ruoyi.wear.device.dto.CapabilityDto;

/**
 * Model-scoped capabilities. Type name (helmet) never implies video.
 */
public final class DeviceCapability
{
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private DeviceCapability()
    {
    }

    public static boolean supports(String capabilitiesJson, String feature)
    {
        if (feature == null || feature.trim().isEmpty())
        {
            return false;
        }
        CapabilityDto dto = parse(capabilitiesJson);
        String key = feature.trim();
        return dto.getAttributes().contains(key)
                || dto.getEvents().contains(key)
                || dto.getActions().contains(key);
    }

    public static CapabilityDto parse(String capabilitiesJson)
    {
        CapabilityDto dto = new CapabilityDto();
        if (capabilitiesJson == null || capabilitiesJson.trim().isEmpty())
        {
            return dto;
        }
        try
        {
            JsonNode root = MAPPER.readTree(capabilitiesJson);
            dto.setProtocolVersion(text(root, "protocolVersion"));
            dto.setAttributes(stringList(root.get("attributes")));
            dto.setEvents(stringList(root.get("events")));
            dto.setActions(stringList(root.get("actions")));
            return dto;
        }
        catch (Exception ex)
        {
            return dto;
        }
    }

    public static String toJson(CapabilityDto dto)
    {
        if (dto == null)
        {
            dto = new CapabilityDto();
        }
        try
        {
            return MAPPER.writeValueAsString(dto);
        }
        catch (Exception ex)
        {
            return "{\"protocolVersion\":null,\"attributes\":[],\"events\":[],\"actions\":[]}";
        }
    }

    private static String text(JsonNode root, String field)
    {
        JsonNode node = root.get(field);
        return node == null || node.isNull() ? null : node.asText();
    }

    private static List<String> stringList(JsonNode node)
    {
        if (node == null || !node.isArray())
        {
            return new ArrayList<String>();
        }
        List<String> values = new ArrayList<String>();
        for (JsonNode item : node)
        {
            if (item != null && !item.isNull())
            {
                values.add(item.asText());
            }
        }
        return values;
    }

    public static List<String> empty()
    {
        return Collections.emptyList();
    }
}
