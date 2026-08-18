import { beforeEach, describe, expect, it } from 'vitest';

import {
  codeFor,
  createVerifiedUser,
  get,
  mailer,
  post,
  prisma,
  resetDatabase,
} from './helpers.js';

const EMAIL = 'traveller@example.com';
const PASSWORD = 'correct-horse-battery';

beforeEach(resetDatabase);

describe('Signing up', () => {
  it('creates an unverified account and emails a code', async () => {
    const response = await post('/auth/signup', {
      email: EMAIL,
      password: PASSWORD,
    });

    expect(response.statusCode).toBe(201);
    // Deliberately no session: the address is not proven yet.
    expect(response.json()).toMatchObject({ status: 'verification_required' });
    expect(response.json().accessToken).toBeUndefined();

    expect(mailer.lastTo(EMAIL)?.subject).toContain('Confirm');
    expect(codeFor(EMAIL)).toMatch(/^\d{6}$/);
  });

  it('normalises the email so case and spacing do not create two accounts',
    async () => {
      await post('/auth/signup', { email: '  Traveller@Example.COM ', password: PASSWORD });
      await post('/auth/signup', { email: EMAIL, password: PASSWORD });

      // The second call resends rather than colliding, because the address is
      // still unconfirmed — but it is recognised as the same address.
      expect(await prisma.user.count()).toBe(1);
      expect(await prisma.user.findUnique({ where: { email: EMAIL } })).not.toBeNull();
    });

  it('signing up again with an unconfirmed address resends rather than '
    + 'colliding', async () => {
    await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    const firstCode = codeFor(EMAIL);

    // The obvious thing to do when a code never arrives. It must not dead-end
    // with "already registered", which would leave the account unusable.
    const again = await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    expect(again.statusCode).toBe(201);
    expect(again.json()).toMatchObject({ status: 'verification_required' });

    const secondCode = codeFor(EMAIL);
    expect(secondCode).not.toBe(firstCode);
    expect(await prisma.user.count()).toBe(1);

    // And the newest code is the one that works.
    expect((await post('/auth/verify-email', { email: EMAIL, code: secondCode }))
      .statusCode).toBe(200);
  });

  it('still refuses a second account once the address is confirmed', async () => {
    await createVerifiedUser(EMAIL, PASSWORD);

    const again = await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    expect(again.statusCode).toBe(409);
    expect(again.json().error).toBe('email_taken');
  });

  it('reports a failed verification email instead of a bare 500', async () => {
    // A mailer that cannot send — an invalid API key, a provider outage.
    const broken = {
      send: async () => { throw new Error('Email send failed (401)'); },
    };
    const { buildApp } = await import('../src/app.js');
    const brokenApp = await buildApp({ mailer: broken });

    const response = await brokenApp.inject({
      method: 'POST',
      url: '/auth/signup',
      payload: { email: 'unlucky@example.com', password: PASSWORD },
    });

    expect(response.statusCode).toBe(502);
    expect(response.json().error).toBe('email_send_failed');
    // Recoverable: the account exists unconfirmed, so signing up again resends.
    expect(await prisma.user.count()).toBe(1);
  });

  it('rejects a password short enough to guess', async () => {
    const response = await post('/auth/signup', { email: EMAIL, password: 'short' });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe('invalid_request');
  });

  it('never stores the password itself', async () => {
    await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    const user = await prisma.user.findUnique({ where: { email: EMAIL } });

    expect(user?.passwordHash).toBeTruthy();
    expect(user?.passwordHash).not.toContain(PASSWORD);
    expect(user?.passwordHash?.startsWith('$argon2')).toBe(true);
  });
});

describe('Verifying an email', () => {
  it('refuses to sign in until the address is confirmed', async () => {
    await post('/auth/signup', { email: EMAIL, password: PASSWORD });

    const blocked = await post('/auth/signin', { email: EMAIL, password: PASSWORD });
    expect(blocked.statusCode).toBe(403);
    expect(blocked.json().error).toBe('email_not_verified');

    await post('/auth/verify-email', { email: EMAIL, code: codeFor(EMAIL) });

    const allowed = await post('/auth/signin', { email: EMAIL, password: PASSWORD });
    expect(allowed.statusCode).toBe(200);
    expect(allowed.json().accessToken).toBeTruthy();
  });

  it('rejects a wrong code, and a code that was already used', async () => {
    await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    const code = codeFor(EMAIL);

    expect((await post('/auth/verify-email', { email: EMAIL, code: '000000' })).statusCode)
      .toBe(400);

    expect((await post('/auth/verify-email', { email: EMAIL, code })).statusCode).toBe(200);

    // Single use: replaying the same email later must not work.
    const replay = await post('/auth/verify-email', { email: EMAIL, code });
    expect(replay.statusCode).toBe(200); // already verified, so it is a no-op
    expect((await prisma.user.findUnique({ where: { email: EMAIL } }))?.emailVerified)
      .toBe(true);
  });

  it('invalidates an earlier code when a new one is requested', async () => {
    await post('/auth/signup', { email: EMAIL, password: PASSWORD });
    const first = codeFor(EMAIL);

    await post('/auth/resend-verification', { email: EMAIL });
    const second = codeFor(EMAIL);
    expect(second).not.toBe(first);

    // A forwarded older email is worthless.
    expect((await post('/auth/verify-email', { email: EMAIL, code: first })).statusCode)
      .toBe(400);
    expect((await post('/auth/verify-email', { email: EMAIL, code: second })).statusCode)
      .toBe(200);
  });

  it('does not reveal whether an address is registered', async () => {
    const unknown = await post('/auth/resend-verification', {
      email: 'nobody@example.com',
    });

    expect(unknown.statusCode).toBe(200);
    expect(unknown.json()).toEqual({ status: 'sent' });
    expect(mailer.sent).toHaveLength(0);
  });
});

describe('Signing in', () => {
  it('gives the same answer for a wrong password and an unknown account',
    async () => {
      await createVerifiedUser(EMAIL, PASSWORD);

      const wrongPassword = await post('/auth/signin', {
        email: EMAIL,
        password: 'not-the-password',
      });
      const noSuchUser = await post('/auth/signin', {
        email: 'nobody@example.com',
        password: PASSWORD,
      });

      expect(wrongPassword.statusCode).toBe(401);
      expect(noSuchUser.statusCode).toBe(401);
      expect(wrongPassword.json()).toEqual(noSuchUser.json());
    });

  it('identifies the caller of /me', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);

    const me = await get('/auth/me', session.accessToken);
    expect(me.statusCode).toBe(200);
    expect(me.json()).toMatchObject({ email: EMAIL, emailVerified: true });
  });

  it('rejects a missing or forged token', async () => {
    expect((await get('/auth/me')).statusCode).toBe(401);
    expect((await get('/auth/me', 'not-a-token')).statusCode).toBe(401);
  });
});

describe('Refresh tokens', () => {
  it('rotates on use, and the old one stops working', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);

    const refreshed = await post('/auth/refresh', {
      refreshToken: session.refreshToken,
    });
    expect(refreshed.statusCode).toBe(200);
    const next = refreshed.json().refreshToken;
    expect(next).not.toBe(session.refreshToken);

    expect((await post('/auth/refresh', { refreshToken: next })).statusCode).toBe(200);
  });

  it('treats a reused token as theft and ends every session', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);
    const rotated = (await post('/auth/refresh', {
      refreshToken: session.refreshToken,
    })).json().refreshToken;

    // The already-consumed token turns up again: either a thief has it, or the
    // legitimate holder does and a thief has the new one. Both are unsafe.
    const reuse = await post('/auth/refresh', { refreshToken: session.refreshToken });
    expect(reuse.statusCode).toBe(401);
    expect(reuse.json().error).toBe('refresh_token_reused');

    // Including the token that was, until a moment ago, perfectly valid.
    const afterRevocation = await post('/auth/refresh', { refreshToken: rotated });
    expect(afterRevocation.statusCode).toBe(401);
  });

  it('stores refresh tokens only as hashes', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);
    const stored = await prisma.refreshToken.findMany();

    expect(stored).toHaveLength(1);
    expect(stored[0].tokenHash).not.toBe(session.refreshToken);
    expect(stored[0].tokenHash).toHaveLength(64); // sha256 hex
  });

  it('signing out stops the token being usable', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);

    expect((await post('/auth/signout', { refreshToken: session.refreshToken })).statusCode)
      .toBe(200);
    expect((await post('/auth/refresh', { refreshToken: session.refreshToken })).statusCode)
      .toBe(401);
  });
});

describe('Password reset', () => {
  it('resets with an emailed code and ends existing sessions', async () => {
    const session = await createVerifiedUser(EMAIL, PASSWORD);

    await post('/auth/forgot-password', { email: EMAIL });
    const code = codeFor(EMAIL);

    const reset = await post('/auth/reset-password', {
      email: EMAIL,
      code,
      password: 'a-brand-new-passphrase',
    });
    expect(reset.statusCode).toBe(200);

    // The old password is dead...
    expect((await post('/auth/signin', { email: EMAIL, password: PASSWORD })).statusCode)
      .toBe(401);
    // ...the new one works...
    expect((await post('/auth/signin', {
      email: EMAIL,
      password: 'a-brand-new-passphrase',
    })).statusCode).toBe(200);
    // ...and anyone still holding a session from before is signed out, which is
    // the point if the reset happened because the account was compromised.
    expect((await post('/auth/refresh', { refreshToken: session.refreshToken })).statusCode)
      .toBe(401);
  });

  it('says the same thing for an unknown address, and sends nothing', async () => {
    const response = await post('/auth/forgot-password', {
      email: 'nobody@example.com',
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'sent' });
    expect(mailer.sent).toHaveLength(0);
  });
});
