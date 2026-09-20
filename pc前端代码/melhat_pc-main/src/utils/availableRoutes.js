// Backend menus can include modules not shipped in this PC frontend.
// Keep only routable entries; do not mutate backend menus or permissions.
export function availableRoutes(routes, views) {
  const containers = new Set(['Layout', 'ParentView']);
  return (routes || []).flatMap((route) => {
    const external = /^https?:\/\//.test(route.path || '') || route.component === 'InnerLink';
    const container = containers.has(route.component);
    if (!external && !container && route.component && !views.has(route.component)) return [];
    const result = { ...route };
    if (route.children) result.children = availableRoutes(route.children, views);
    if (container && !external && !result.children?.length) return [];
    return [result];
  });
}
