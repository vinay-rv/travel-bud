/**
 * Sending email.
 *
 * Behind an interface for the usual reason — tests must not send real mail —
 * but the production path is a real provider, not a console stub. Resend is the
 * adapter here because it is a single authenticated POST with no SDK to add;
 * swapping to Postmark or SES means rewriting one function.
 */
import { env } from './env.js';

export type Mail = {
  to: string;
  subject: string;
  text: string;
};

export interface Mailer {
  send(mail: Mail): Promise<void>;
}

/**
 * Collects mail instead of sending it. Used by tests, which assert on the code
 * that would have been emailed.
 */
export class CapturingMailer implements Mailer {
  readonly sent: Mail[] = [];

  async send(mail: Mail): Promise<void> {
    this.sent.push(mail);
  }

  /** The most recent mail to an address, for asserting on a flow. */
  lastTo(email: string): Mail | undefined {
    return [...this.sent].reverse().find((mail) => mail.to === email);
  }

  clear(): void {
    this.sent.length = 0;
  }
}

export class ResendMailer implements Mailer {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
  ) {}

  async send(mail: Mail): Promise<void> {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${this.apiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        from: this.from,
        to: [mail.to],
        subject: mail.subject,
        text: mail.text,
      }),
    });

    if (!response.ok) {
      // Deliberately loud. A silently dropped verification email looks to the
      // user like a broken sign-up with no explanation.
      const detail = await response.text().catch(() => '');
      throw new Error(`Email send failed (${response.status}): ${detail}`);
    }
  }
}

/**
 * The mailer this process should use.
 *
 * Refuses to start without credentials rather than quietly degrading to a
 * no-op: an account system whose verification emails vanish is worse than one
 * that admits it cannot send them.
 */
export function createMailer(): Mailer {
  if (!env.RESEND_API_KEY || !env.MAIL_FROM) {
    throw new Error(
      'Email is not configured. Set RESEND_API_KEY and MAIL_FROM ' +
        '(e.g. "Packmate <hello@yourdomain.com>").',
    );
  }
  return new ResendMailer(env.RESEND_API_KEY, env.MAIL_FROM);
}
