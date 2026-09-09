package com.ruoyi.wear.device.dto;

import java.util.ArrayList;
import java.util.List;

public class CapabilityDto
{
    private String protocolVersion;
    private List<String> attributes = new ArrayList<String>();
    private List<String> events = new ArrayList<String>();
    private List<String> actions = new ArrayList<String>();

    public String getProtocolVersion() { return protocolVersion; }
    public void setProtocolVersion(String protocolVersion) { this.protocolVersion = protocolVersion; }
    public List<String> getAttributes() { return attributes; }
    public void setAttributes(List<String> attributes) { this.attributes = attributes == null ? new ArrayList<String>() : attributes; }
    public List<String> getEvents() { return events; }
    public void setEvents(List<String> events) { this.events = events == null ? new ArrayList<String>() : events; }
    public List<String> getActions() { return actions; }
    public void setActions(List<String> actions) { this.actions = actions == null ? new ArrayList<String>() : actions; }
}
