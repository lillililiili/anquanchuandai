export function videoGridPage(cameras, layout, requestedPage = 0) {
  const capacity = layout === '3×3' ? 9 : 8;
  const pages = Math.max(1, Math.ceil(cameras.length / capacity));
  const page = Math.max(0, Math.min(pages - 1, Number.isFinite(requestedPage) ? Math.floor(requestedPage) : 0));
  return { capacity, pages, page, total: cameras.length, items: cameras.slice(page * capacity, (page + 1) * capacity),
    first: cameras.length ? page * capacity + 1 : 0, last: Math.min((page + 1) * capacity, cameras.length) };
}

export function nextVideoFocus(cameras, currentId) {
  if (!cameras.length) return '';
  const current = cameras.findIndex(person => person.id === currentId);
  return cameras[(current + 1) % cameras.length].id;
}
