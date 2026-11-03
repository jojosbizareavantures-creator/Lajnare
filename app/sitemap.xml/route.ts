import {canonicalOrigin, PUBLIC_PATHS} from '@/lib/site-config';
export function GET(request: Request) {
  const origin = canonicalOrigin(new URL(request.url).host);
  return new Response(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${PUBLIC_PATHS.map(path => `<url><loc>${origin}${path}</loc></url>`).join('')}</urlset>`, {
    headers: {'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600'},
  });
}
