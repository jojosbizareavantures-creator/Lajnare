import {canonicalOrigin} from '@/lib/site-config';
export function GET(request: Request) {
  const origin = canonicalOrigin(new URL(request.url).host);
  return new Response([
    'User-agent: *', 'Allow: /landing',
    ...['/adminpanel', '/chatterportal', '/referrer', '/api/', '/auth/', '/login', '/register', '/forgot-password', '/reset-password', '/apply'].map(path => `Disallow: ${path}`),
    `Sitemap: ${origin}/sitemap.xml`, '',
  ].join('\n'), {headers: {'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'public, max-age=3600'}});
}
