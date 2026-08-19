/**
 * Sending email.
 *
 * Behind an interface for the usual reason — tests must not send real mail —
 * with three implementations: a real provider, a capturing fake for tests, and
 * a console driver for developing without a verified sending domain.
 *
 * Resend is the provider adapter because it is a single authenticated POST
 * with no SDK to add; swapping to Postmark or SES means rewriting one function.
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
 * Prints mail to the log instead of sending it.
 *
 * For developing before a sending domain is verified: the sign-up flow is fully
 * exercisable because the code is right there in the server output.
 *
 * This is a development tool and the code says so at every opportunity — the
 * banner below, the startup warning, and a hard refusal to run in production.
 * A console mailer reaching production would mean every verification code both
 * fails to arrive *and* is written to the logs, which is the worst of both.
 */
export class ConsoleMailer implements Mailer {
  async send(mail: Mail): Promise<void> {
    const line = '─'.repeat(64);
    process.stdout.write(
      `\n${line}\n` +
        `  DEV MAILER — not sent, printed. To: ${mail.to}\n` +
        `  ${mail.subject}\n${line}\n` +
        `${mail.text}\n${line}\n\n`,
    );
  }
}

/**
 * The mailer this process should use.
 *
 * With credentials, the real provider. Without them, the console driver — but
 * only outside production, and only after saying loudly what it is doing.
 * Quietly degrading to a no-op would be the worst option: an account system
 * whose verification emails vanish without a word.
 */
export function createMailer(): Mailer {
  const configured = Boolean(env.RESEND_API_KEY && env.MAIL_FROM);

  if (configured) {
    return new ResendMailer(env.RESEND_API_KEY!, env.MAIL_FROM!);
  }

  if (env.NODE_ENV === 'production') {
    throw new Error(
      'Email is not configured. Set RESEND_API_KEY and MAIL_FROM ' +
        '(e.g. "Packmate <hello@yourdomain.com>"). The console mailer is a ' +
        'development tool and will not run in production.',
    );
  }

  process.stdout.write(
    '\n*** Email is not configured — verification codes will be PRINTED ***\n' +
      '*** to this log, not emailed. Development only. Set RESEND_API_KEY ***\n' +
      '*** and MAIL_FROM to send real mail.                              ***\n\n',
  );
  return new ConsoleMailer();
}
