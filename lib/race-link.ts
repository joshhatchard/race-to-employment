export function normaliseRaceCode(value?: string | null) {
  const code = value?.trim().toUpperCase();
  return code && /^[A-Z0-9]{1,12}$/.test(code) ? code : null;
}

const configuredSiteUrl=process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/,'');
export const publicSiteUrl=configuredSiteUrl&&!/^https?:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/i.test(configuredSiteUrl)
  ? configuredSiteUrl
  : 'https://breadsup.vercel.app';

export function raceInviteUrl(code:string) {
  return `${publicSiteUrl}/r/${encodeURIComponent(code)}`;
}
