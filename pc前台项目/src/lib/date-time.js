const beijingFormatter = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});

export function formatBeijingDateTime(value) {
  if (typeof value !== 'string') return '—';
  const match = value.trim().match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:?\d{2})?$/);
  if (!match) return '—';
  const [, date, hour, minute, second = '00', fraction, zone] = match;
  const calendar = new Date(`${date}T00:00:00Z`);
  if (!Number.isFinite(calendar.getTime()) || calendar.toISOString().slice(0, 10) !== date || Number(hour) > 23 || Number(minute) > 59 || Number(second) > 59) return '—';
  // Legacy records without an offset were already stored in Beijing local time.
  // Truncate backend nanoseconds to milliseconds before parsing in the browser.
  const offset = zone ? zone.replace(/([+-]\d{2})(\d{2})$/, '$1:$2') : '+08:00';
  const instant = new Date(`${date}T${hour}:${minute}:${second}${fraction ? '.' + fraction.slice(0, 3).padEnd(3, '0') : ''}${offset}`);
  if (!Number.isFinite(instant.getTime())) return '—';
  const parts = Object.fromEntries(beijingFormatter.formatToParts(instant).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
}
