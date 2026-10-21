import {CSSProperties, useId} from 'react';

export type LogoTone = 'onViolet' | 'onLight';
export type LogoVariant = 'horizontal' | 'stacked' | 'icon';

type LogoProps = {
  variant?: LogoVariant;
  size?: number;
  tone?: LogoTone;
  className?: string;
  style?: CSSProperties;
};

/** Select a logo tone from the surface theme instead of picking logo colours at call sites. */
export function logoToneForSurface(surface: 'light' | 'violet'): LogoTone {
  return surface === 'violet' ? 'onViolet' : 'onLight';
}

function BreadSlice() {
  return <g>
    <path d="M14 28C6 26 5 14 14 11C20 6 29 7 32 10C35 7 44 6 50 11C59 14 58 26 50 28V50C50 54 48 57 44 57H20C16 57 14 54 14 50Z" fill="#E59A3B" />
    <path d="M14 28C6 26 5 14 14 11C20 6 29 7 32 10C35 7 44 6 50 11C59 14 58 26 50 28V50C50 54 48 57 44 57H20C16 57 14 54 14 50Z" fill="#FFDFA3" transform="translate(32 34) scale(.78) translate(-32 -34)" />
    <circle cx="26" cy="37" r="2.6" fill="#1E1245" />
    <circle cx="38" cy="37" r="2.6" fill="#1E1245" />
    <path d="M27 44q5 5 10 0" fill="none" stroke="#1E1245" strokeWidth="2.6" strokeLinecap="round" />
  </g>;
}

export function Logo({variant = 'horizontal', size = 40, tone = 'onLight', className, style}: LogoProps) {
  const clipId = `breads-up-clip-${useId().replace(/:/g, '')}`;
  const iconSize = Math.max(size, variant === 'stacked' ? 40 : 24);
  const isLight = tone === 'onLight';
  const toaster = isLight ? '#5B3CDD' : '#FFFFFF';
  const slot = isLight ? '#3D24A8' : '#B9AEF2';
  const accent = isLight ? (iconSize < 40 ? '#D12C85' : '#E8499A') : '#FF9BCB';
  const wordStyle: CSSProperties = {
    color: isLight ? '#1E1245' : '#FFFFFF',
    fontFamily: 'var(--font-poppins), Poppins, system-ui, sans-serif',
    fontWeight: 800,
    letterSpacing: '-.04em',
  };
  const icon = <svg viewBox="0 0 100 80" width={iconSize * 1.25} height={iconSize} aria-hidden={variant !== 'icon'} focusable="false">
    <defs><clipPath id={clipId}><rect x="0" y="0" width="100" height="47" /></clipPath></defs>
    <rect x="6" y="36" width="88" height="42" rx="16" fill={toaster} />
    <rect x="10" y="42" width="80" height="9" rx="4.5" fill={slot} />
    <g clipPath={`url(#${clipId})`}>
      <g transform="translate(8 16) rotate(-7 20 20) scale(.7)"><BreadSlice /></g>
      <g transform="translate(52 10) rotate(7 20 20) scale(.7)"><BreadSlice /></g>
    </g>
    <rect x="10" y="46.5" width="80" height="4.5" rx="2.25" fill={slot} />
    <rect x="80" y="58" width="9" height="12" rx="4.5" fill={isLight ? '#E8499A' : '#FF9BCB'} />
  </svg>;

  if (variant === 'icon') {
    return <span className={className} style={{display: 'inline-flex', lineHeight: 0, ...style}} role="img" aria-label="Breads Up!">{icon}</span>;
  }

  if (variant === 'stacked') {
    return <span className={className} style={{alignItems: 'center', display: 'inline-flex', flexDirection: 'column', gap: Math.round(iconSize * .15), lineHeight: .95, textAlign: 'center', ...style}} role="img" aria-label="Breads Up!">
      {icon}
      <span style={{...wordStyle, fontSize: Math.round(iconSize * .7), lineHeight: 1, whiteSpace: 'nowrap'}}>breads <span style={{color: accent}}>up!</span></span>
    </span>;
  }

  return <span className={className} style={{alignItems: 'center', display: 'inline-flex', gap: 12, lineHeight: 1, ...style}} role="img" aria-label="Breads Up!">
    {icon}
    <span style={{...wordStyle, fontSize: Math.round(iconSize * .7), lineHeight: 1, whiteSpace: 'nowrap'}}>breads <span style={{color: accent}}>up!</span></span>
  </span>;
}
