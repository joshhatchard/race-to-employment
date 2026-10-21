# Breads Up!

A mobile-first, Google-authenticated job-search race for a group of friends. It uses Next.js, Supabase Realtime, and an installable PWA shell.

## Run locally

1. Install Node.js 20+ and run `npm install`.
2. Copy `.env.example` to `.env.local` and fill in the Supabase URL and anon key.
3. Run `npm run dev`, then open `http://localhost:3000`.

## Deploy checklist

1. Create a free Supabase project. In **SQL Editor**, paste and run [`supabase/schema.sql`](supabase/schema.sql). Before doing so, replace `YOUR_EMAIL@gmail.com` on the last line with the Google email that should host the race.
2. In Google Cloud, create a project. Configure the OAuth consent screen as **External**; add friends as test users, or publish the app to remove the test-user limit. Create a **Web application** OAuth client, use the redirect URI Supabase displays at **Authentication > Providers > Google**, then paste its client ID and secret into that Supabase provider.
3. In Supabase **Authentication > URL Configuration**, set Site URL to the Vercel URL. Add both that URL and `http://localhost:3000` to Redirect URLs.
4. Push this repository to GitHub, import it into Vercel, and add `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_RACE_CODE=SUEDE26` as environment variables. Deploy to the default `*.vercel.app` URL.
5. Test with two Google accounts: sign in, join, log applications, and confirm live updates. Confirm logging before launch is blocked. To test countdown, temporarily run:
   ```sql
   update public.groups set start_at = now() + interval '2 minutes' where code = 'SUEDE26';
   ```
   Restore launch time with:
   ```sql
   update public.groups set start_at = '2026-10-25 06:00:00+00' where code = 'SUEDE26';
   ```
6. Troubleshooting:
   - `redirect_uri_mismatch`: copy the exact callback URI Supabase shows into Google Cloud.
   - `access blocked: app not verified`: add users to the OAuth consent-screen test users, or publish the consent screen.
   - Project paused: open the Supabase dashboard and restore the free project, then sign in again.
   - iOS PWA signs out: make sure the Vercel HTTPS URL is configured as Site URL and Redirect URL before using **Add to Home Screen**.

## Defaults and scope

`NEXT_PUBLIC_RACE_CODE` defaults to `SUEDE26`. The visual/audio preference is device-local; sound is muted by default. `NEXT_PUBLIC_ENABLE_CREATE=true` is reserved for later UI expansion.
