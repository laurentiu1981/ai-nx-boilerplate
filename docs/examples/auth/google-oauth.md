# Google login (NestJS + Passport + JWT cookie)

The pattern used by `crk-mind-cache` / `crk-agent-gallery` / `crk-stocks` / `ai-chat`:
Passport Google OAuth20 strategy on the api, a JWT minted into an **httpOnly cookie**,
and a full-page redirect flow on the web side. The whole feature is **optional** —
when the Google env vars are unset the app boots and runs normally; only the
sign-in route returns 503.

## Env variables

All consumed by the **api** (the web app has no Google vars):

```bash
# ── Google OAuth (optional) ──────────────────────────────────────────────────
# Without these the app runs fine, but the "Continue with Google" button returns
# 503. Create credentials at https://console.cloud.google.com/apis/credentials
# (OAuth client → Web application) and add the callback URL below as an
# "Authorized redirect URI".
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-google-client-secret
GOOGLE_CALLBACK_URL=http://localhost:{{port_band}}20/api/auth/google/callback
```

Related vars: `FRONTEND_URL` (redirect target after login), `JWT_SECRET`,
`JWT_EXPIRES_IN`, `NODE_ENV` (controls the cookie's `secure` flag).

**Callback URL pattern:** `<API_ORIGIN>/api/auth/google/callback` — the api's global
prefix `api` plus the controller route `auth/google/callback`. In production this is
`https://{{domain}}/api/auth/google/callback` (single origin, path-routed through the
reverse proxy — see `../reverse-proxy.md`). The exact string must be registered as an
"Authorized redirect URI" in the Google Cloud console. Register BOTH the dev
(localhost) and prod URLs on the same OAuth client, or use two clients.

## Implementation shape

Files under `apps/api/src/app/auth/`:

**`google.strategy.ts`** — construct with placeholder creds so Nest DI never fails
when the feature is unconfigured:

```ts
@Injectable()
export class GoogleStrategy extends PassportStrategy(Strategy, 'google') {
  constructor(config: ConfigService) {
    super({
      clientID: config.get('GOOGLE_CLIENT_ID') || 'not-configured',
      clientSecret: config.get('GOOGLE_CLIENT_SECRET') || 'not-configured',
      callbackURL: config.get('GOOGLE_CALLBACK_URL') || 'not-configured',
      scope: ['email', 'profile'],
    });
  }
  validate(_at: string, _rt: string, profile: Profile): GoogleProfile {
    return {
      googleId: profile.id,
      email: profile.emails?.[0]?.value ?? '',
      name: profile.displayName,
      avatarUrl: profile.photos?.[0]?.value,
    };
  }
}
```

**`google-oauth.guard.ts`** — extends `AuthGuard('google')`; before delegating,
check both `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set and throw
`ServiceUnavailableException('Google sign-in is not configured')` otherwise.
This is what makes the feature degrade gracefully.

**`auth.controller.ts`**:

```ts
@Controller('auth')
export class AuthController {
  @Get('google') @UseGuards(GoogleOAuthGuard)
  googleAuth(): void { /* guard redirects to Google */ }

  @Get('google/callback') @UseGuards(GoogleOAuthGuard)
  async googleCallback(@Req() req, @Res() res) {
    const user = await this.auth.validateGoogleUser(req.user as GoogleProfile); // upsert user
    const token = await this.auth.signToken(user);                              // mint JWT
    res.cookie('access_token', token, {
      httpOnly: true, sameSite: 'lax',
      secure: this.config.get('NODE_ENV') === 'production',
      maxAge: SEVEN_DAYS_MS, path: '/',
    });
    res.redirect(this.config.get('FRONTEND_URL') ?? 'http://localhost:{{port_band}}10');
  }

  @Get('me') @UseGuards(JwtAuthGuard) me(@CurrentUser() u) { return this.auth.me(u.sub); }
  @Post('logout') logout(@Res({ passthrough: true }) res) {
    res.clearCookie('access_token', { path: '/' });
    return { ok: true };
  }
}
```

**`auth.service.ts`** — `validateGoogleUser` upserts the user by `googleId`/email;
`signToken` signs `{ sub, email, name, role }` via `@nestjs/jwt`
(`JwtModule.registerAsync` with `JWT_SECRET` / `JWT_EXPIRES_IN`).

**`jwt-auth.guard.ts`** — a custom guard (not passport-jwt) that accepts either the
`access_token` cookie (verified with `jwt.verify`) or, if the project has API keys
(CLI / browser extension clients), `Authorization: Bearer <api-key>` checked against
an `api_keys` table. Make it work for both REST and GraphQL execution contexts.

## Frontend flow

No popup, no client-side token handling — the cookie is set by the callback:

```ts
// auth-context.tsx
const loginUrl = `${config.apiUrl}/auth/google`;
const logout = () => fetch(`${apiUrl}/auth/logout`, { method: 'POST', credentials: 'include' });

// "Continue with Google" button
onClick={() => { window.location.href = loginUrl; }}
```

## Why single origin matters

Serving web and api from one domain (path-routed reverse proxy) means the JWT cookie
is first-party and no CORS setup is needed. Keep it that way in prod. For a local
http trial of the prod stack, set `NODE_ENV=development` so the cookie isn't
Secure-only (it won't stick over plain `http://localhost`).

## Never commit real credentials

`GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` go in `.env` (gitignored) only.
`.env.example` gets placeholder values.
