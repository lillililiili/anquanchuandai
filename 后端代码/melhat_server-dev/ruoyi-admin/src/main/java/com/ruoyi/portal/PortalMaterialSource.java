package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.Section;
import com.ruoyi.portal.PortalS2Models.Material;
/** Metadata only; no file URLs. Historical associations require evidence and object visibility. */
public interface PortalMaterialSource {
    default boolean visible(String actor,String site,String kind,String id) { return false; }
    default Section<List<Material>> materials(String actor,String site) { return Section.missing("MATERIAL_NOT_INTEGRATED"); }
    default Material material(String actor,String site,String id) { return null; }
}
