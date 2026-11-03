// Retain the current host while the custom domain is connected.
export const PRODUCTION_ORIGIN = new URL(process.env.NEXT_PUBLIC_SITE_URL || 'https://evzonchatting.com').origin;
export const LEGACY_ORIGIN = 'https://evzon-operations.socialrook33.chatgpt.site';
export const SITE_ORIGINS = [PRODUCTION_ORIGIN, 'https://www.evzonchatting.com', LEGACY_ORIGIN] as const;
export const PUBLIC_PATHS = ['/landing', '/landing/how-it-works', '/landing/earnings', '/landing/training', '/landing/referrals', '/landing/faq'] as const;

export function canonicalOrigin(host: string | null): string {
  // Preview hosts and untrusted Host headers never enter metadata or sitemaps.
  return host?.toLowerCase() === new URL(LEGACY_ORIGIN).host ? LEGACY_ORIGIN : PRODUCTION_ORIGIN;
}

export function authRedirectUrl(request: Request, recovery = false): string {
  const url = new URL(request.url);
  const local = process.env.NODE_ENV !== 'production' &&
    ['localhost', '127.0.0.1', 'terminal.local'].includes(url.hostname);
  const deploymentOrigins = [process.env.VERCEL_URL, process.env.VERCEL_PROJECT_PRODUCTION_URL]
    .filter((host): host is string => !!host && /^[a-z0-9.-]+\.vercel\.app$/i.test(host))
    .map(host => 'https://' + host);
  if (!(SITE_ORIGINS as readonly string[]).includes(url.origin) && !deploymentOrigins.includes(url.origin) && !local) {
    throw new Error('Unrecognized website address. Open Evzon using its official website.');
  }
  return new URL(recovery ? '/auth/confirm?recovery=1' : '/auth/confirm', url.origin).href;
}

export function privatePath(path: string): boolean {
  return ['/api', '/auth', '/adminpanel', '/chatterportal', '/referrer', '/login', '/register', '/forgot-password', '/reset-password', '/apply']
    .some(prefix => path === prefix || path.startsWith(prefix + '/'));
}
