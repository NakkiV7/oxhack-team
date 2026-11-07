import { analyticsRequest, cleanupAnalytics } from './analytics.ts';
import { createAuthHandler, cleanup } from './auth.ts';
import { createNativeAuthHandler, type NativeEnv } from './native-auth.ts';
import { context, cleanupNative } from './native-sessions.ts';
export interface SiteEnv extends NativeEnv { ASSETS: { fetch(request: Request): Promise<Response> }; }
function secured(response: Response, path: string): Response {
  const headers = new Headers(response.headers);
  headers.set('X-Content-Type-Options','nosniff');
  headers.set('Referrer-Policy','no-referrer');
  headers.set('Strict-Transport-Security','max-age=31536000');
  headers.set('X-Frame-Options','DENY');
  headers.set('Permissions-Policy','camera=(), microphone=(), geolocation=(), payment=()');
  if (!path.startsWith('/api/')) headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'");
  if (path.startsWith('/account/') || path.startsWith('/api/')) headers.set('Cache-Control','no-store');
  return new Response(response.body,{status:response.status,statusText:response.statusText,headers});
}
export default {
  async fetch(request: Request, env: SiteEnv): Promise<Response> {
    const url=new URL(request.url);
    if (url.protocol==='http:') {url.protocol='https:';return Response.redirect(url.href,308);}
    if (url.pathname==='/.well-known/apple-app-site-association') return secured(Response.json({webcredentials:{apps:['952HTWFJX7.com.omarchoudhry.spottr']}}),url.pathname);
    if (url.pathname==='/api/health') return secured(Response.json({service:'Spottr',status:'available'}),url.pathname);
    if (url.pathname.startsWith('/api/analytics/')) return secured(await analyticsRequest(request,env.DB),url.pathname);
    if (url.pathname.startsWith('/api/native/v1/')) return secured(await createNativeAuthHandler(env)(request),url.pathname);
    if (url.pathname.startsWith('/api/')) return secured(await createAuthHandler(env)(request),url.pathname);
    return secured(await env.ASSETS.fetch(request),url.pathname);
  },
  async scheduled(_event: unknown, env: SiteEnv): Promise<void> { await cleanup(env); await cleanupNative(context(env)); await cleanupAnalytics(env.DB); }
};
