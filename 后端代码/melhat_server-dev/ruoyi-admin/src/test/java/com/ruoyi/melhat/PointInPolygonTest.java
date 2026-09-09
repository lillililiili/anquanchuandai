package com.ruoyi.melhat;

import com.ruoyi.wear.location.PointInPolygon;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PointInPolygonTest {

    @Test
    void demoBoxContainsSamplePoint() {
        List<double[]> ring = Arrays.asList(
                new double[] {117.10, 36.10},
                new double[] {117.14, 36.10},
                new double[] {117.14, 36.14},
                new double[] {117.10, 36.14});
        assertTrue(PointInPolygon.contains(117.12, 36.12, ring));
        assertFalse(PointInPolygon.contains(117.20, 36.20, ring));
        assertFalse(PointInPolygon.contains(117.12, 36.12, Arrays.asList(new double[] {1, 1})));
    }
}
