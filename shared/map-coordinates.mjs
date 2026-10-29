// Coordinate conversion for the GCJ-02 basemap. Preserve source coordinates.
export function coordinateSystem(value) {
  return String(value || "UNKNOWN").toUpperCase().replace(/[-_]/g, "");
}

export function validLonLat(longitude, latitude) {
  if (longitude == null || latitude == null || longitude === "" || latitude === "") return false;
  const lng = Number(longitude), lat = Number(latitude);
  return Number.isFinite(lng) && Number.isFinite(lat) && Math.abs(lng) <= 180 && Math.abs(lat) <= 90 && (lng !== 0 || lat !== 0);
}

export function toMapCoordinates(location) {
  if (!location || !validLonLat(location.longitude, location.latitude)) return null;
  const system = coordinateSystem(location.coordinateSystem);
  const lng = Number(location.longitude), lat = Number(location.latitude);
  if (system === "GCJ02") return [lng, lat];
  if (system !== "WGS84") return null;
  if (lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271) return [lng, lat];
  const x = lng - 105, y = lat - 35, pi = Math.PI;
  let dy = -100 + 2*x + 3*y + .2*y*y + .1*x*y + .2*Math.sqrt(Math.abs(x));
  dy += (20*Math.sin(6*x*pi) + 20*Math.sin(2*x*pi))*2/3;
  dy += (20*Math.sin(y*pi) + 40*Math.sin(y/3*pi))*2/3;
  dy += (160*Math.sin(y/12*pi) + 320*Math.sin(y*pi/30))*2/3;
  let dx = 300 + x + 2*y + .1*x*x + .1*x*y + .1*Math.sqrt(Math.abs(x));
  dx += (20*Math.sin(6*x*pi) + 20*Math.sin(2*x*pi))*2/3;
  dx += (20*Math.sin(x*pi) + 40*Math.sin(x/3*pi))*2/3;
  dx += (150*Math.sin(x/12*pi) + 300*Math.sin(x/30*pi))*2/3;
  const rad = lat/180*pi, magic = 1 - .00669342162296594323*Math.sin(rad)**2;
  const root = Math.sqrt(magic);
  return [lng + dx*180/(6378245/root*Math.cos(rad)*pi), lat + dy*180/((6378245*(1-.00669342162296594323))/(magic*root)*pi)];
}

export function fromMapCoordinates(point, system) {
  const normalized=coordinateSystem(system);
  if(normalized==='GCJ02')return [...point];
  if(normalized!=='WGS84')return null;
  let result=[...point];
  for(let i=0;i<6;i++){
    const projected=toMapCoordinates({longitude:result[0],latitude:result[1],coordinateSystem:'WGS84'});
    result=[result[0]+point[0]-projected[0],result[1]+point[1]-projected[1]];
  }
  return result;
}
