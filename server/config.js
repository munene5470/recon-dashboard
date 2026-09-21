export const ALLOWED_TARGETS = (process.env.ALLOWED_TARGETS || '')
  .split(',')
  .map((value) => value.trim().toLowerCase())
  .filter(Boolean);

export function isAllowedTarget(host) {
  const target = String(host || '').trim().toLowerCase();
  if (!target) return false;
  return ALLOWED_TARGETS.some((allowed) => target === allowed || target.endsWith(`.${allowed}`));
}
