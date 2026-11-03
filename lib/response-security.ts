import {privatePath} from './site-config';

export function secureResponse(request: Request, response: Response): Response {
  const url = new URL(request.url);
  const protectedPage = privatePath(url.pathname);
  const result = new Response(response.body, response);
  result.headers.set('X-Content-Type-Options', 'nosniff');
  result.headers.set('Referrer-Policy', protectedPage ? 'no-referrer' : 'strict-origin-when-cross-origin');
  result.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  // Block unsafe base/form changes without changing the application flows.
  result.headers.set('Content-Security-Policy', "base-uri 'self'; object-src 'none'; form-action 'self'");
  if (url.protocol === 'https:') result.headers.set('Strict-Transport-Security', 'max-age=31536000');
  if (protectedPage) {
    result.headers.set('Cache-Control', 'private, no-store');
    result.headers.set('X-Robots-Tag', 'noindex, nofollow');
  }
  return result;
}
