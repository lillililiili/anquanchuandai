package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.Section;
import com.ruoyi.portal.PortalS2Models.*;
/** Each call is actor/site/purpose scoped. Lists must be complete, not pre-truncated.
 * Implementations must return fresh DTOs and independently check object visibility.
 * Unknown continuity must never be upgraded from a guessed sampling threshold. */
public interface PortalSpatialSource {
    default boolean visible(String actor,String site,String kind,String id,String permission) { return false; }
    default Section<List<DeviceOption>> devices(String actor,String site,Set<String> permissions) { return Section.missing("DEVICE_SOURCE_NOT_INTEGRATED"); }
    default Section<List<LocatedDevice>> locations(String actor,String site) { return Section.missing("LOCATION_NOT_INTEGRATED"); }
    default Section<Track> tracks(String actor,String site,String device,String from,String to) { return Section.missing("TRACK_NOT_INTEGRATED"); }
    default Section<List<Fence>> fences(String actor,String site) { return Section.missing("FENCE_NOT_INTEGRATED"); }
    default Fence fence(String actor,String site,String id) { return null; }
}
