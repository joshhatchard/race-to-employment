import { createServerClient } from '@supabase/ssr';
import { NextResponse } from 'next/server';

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get('code');
  const race = requestUrl.searchParams.get('race');
  const destination = new URL('/', requestUrl.origin);

  if (race && /^[A-Z0-9]{1,12}$/i.test(race)) {
    destination.searchParams.set('race', race.toUpperCase());
  }

  const response = NextResponse.redirect(destination);
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !key || !code) return response;

  const client = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.headers.get('cookie')?.split(';').map(part => {
          const [name, ...value] = part.trim().split('=');
          return { name, value: value.join('=') };
        }) ?? [];
      },
      setAll(cookies) {
        cookies.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const { error } = await client.auth.exchangeCodeForSession(code);
  if (error) {
    destination.searchParams.set('auth_error', 'Sign-in expired. Please try Google sign-in again.');
    response.headers.set('Location', destination.toString());
  }

  return response;
}
