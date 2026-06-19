import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy — Photoboot",
  description: "How Photoboot collects, uses, and protects your data.",
};

const EFFECTIVE = "June 19, 2026";

export default function PrivacyPage() {
  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-12">
      <Link
        href="/"
        className="ig-gradient-text text-lg font-bold tracking-tight"
      >
        Photoboot ✨
      </Link>

      <h1 className="mt-8 text-3xl font-bold tracking-tight">Privacy Policy</h1>
      <p className="mt-1 text-sm text-zinc-500">Effective {EFFECTIVE}</p>

      <div className="prose prose-zinc mt-8 max-w-none text-sm leading-relaxed text-zinc-700">
        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">1. Who we are</h2>
          <p>
            Photoboot is operated by <strong>Blocktech Ventures LLC</strong>.
            This policy describes what we collect when you use a Photoboot
            booth at a private event.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">2. What we collect</h2>
          <ul className="list-disc pl-6">
            <li>
              <strong>Photos</strong> you capture at the booth.
            </li>
            <li>
              <strong>Phone number</strong> (only if you choose to receive
              your photo by SMS).
            </li>
            <li>
              <strong>Email address</strong> (only if you choose to receive
              your photo by email).
            </li>
            <li>
              <strong>Delivery logs</strong> (timestamp, success/failure
              status) needed to confirm we sent your message.
            </li>
          </ul>
          <p>
            We do <strong>not</strong> collect your name, location, device
            identifiers, or marketing-relevant data.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">3. How we use it</h2>
          <p>
            Your contact info is used <strong>only</strong> to send you the
            link to your photo for the event you attended. We do not use it
            for marketing, sell it, or share it for advertising. Photos
            captured at the booth are made available to you via the link sent
            to your phone or email; the event host may also retain a copy as
            the event organizer.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">4. Service providers</h2>
          <p>We rely on these subprocessors to deliver the service:</p>
          <ul className="list-disc pl-6">
            <li>
              <strong>Twilio</strong> — sends SMS messages on our behalf.
            </li>
            <li>
              <strong>Resend</strong> — sends email messages on our behalf.
            </li>
            <li>
              <strong>Supabase</strong> — database + photo storage hosting.
            </li>
            <li>
              <strong>Vercel</strong> — hosting for the website you&apos;re
              reading right now.
            </li>
          </ul>
          <p>
            These providers process your data only to perform the service we
            ask of them.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">5. Retention</h2>
          <p>
            Phone numbers and email addresses are retained for as long as the
            event&apos;s gallery is active (typically through the conclusion
            of the event plus a short follow-up window), then deleted.
            Photos remain available via the original link unless the event
            host deletes them.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">6. Your rights</h2>
          <p>
            You can opt out of SMS at any time by replying <strong>STOP</strong>{" "}
            to a Photoboot message. To request deletion of your photo, phone
            number, or email from our records, contact us at the address
            below — we&apos;ll act on it within 30 days.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">7. Children</h2>
          <p>
            Photoboot is not directed to children under 13. If you believe a
            child under 13 has provided a phone number or email at a booth,
            contact us and we&apos;ll delete the record.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">8. Changes</h2>
          <p>
            We may update this policy. Material changes are reflected by
            updating the &ldquo;Effective&rdquo; date above.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">9. Contact</h2>
          <p>
            Privacy questions or deletion requests:{" "}
            <a href="mailto:hello@blocktech.ventures" className="text-ig-pink underline">
              hello@blocktech.ventures
            </a>
          </p>
        </section>
      </div>

      <p className="mt-12 text-xs text-zinc-400">
        © Blocktech Ventures LLC · See also our{" "}
        <Link href="/terms" className="underline">Terms of Service</Link>.
      </p>
    </main>
  );
}
