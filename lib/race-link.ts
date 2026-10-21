export function normaliseRaceCode(value?: string | null) {
  const code = value?.trim().toUpperCase();
  return code && /^[A-Z0-9]{1,12}$/.test(code) ? code : null;
}
