package com.ruoyi.wear.location;

import java.util.List;

public final class PointInPolygon
{
    private PointInPolygon()
    {
    }

    public static boolean contains(double lng, double lat, List<double[]> ring)
    {
        if (ring == null || ring.size() < 3)
        {
            return false;
        }
        boolean inside = false;
        int n = ring.size();
        for (int i = 0, j = n - 1; i < n; j = i++)
        {
            double[] pi = ring.get(i);
            double[] pj = ring.get(j);
            double xi = pi[0];
            double yi = pi[1];
            double xj = pj[0];
            double yj = pj[1];
            boolean intersect = ((yi > lat) != (yj > lat))
                    && (lng < (xj - xi) * (lat - yi) / (yj - yi + 0.0) + xi);
            if (intersect)
            {
                inside = !inside;
            }
        }
        return inside;
    }
}
