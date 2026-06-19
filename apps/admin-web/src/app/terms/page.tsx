import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms of Service — Photoboot",
  description: "Terms of service for the Photoboot SMS + email photo delivery service.",
};

const EFFECTIVE = "June 19, 2026";

export default function TermsPage() {
  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-12">
      <Link
        href="/"
        className="ig-gradient-text text-lg font-bold tracking-tight"
      >
        Photoboot ✨
      </Link>

      <h1 className="mt-8 text-3xl font-bold tracking-tight">Terms of Service</h1>
      <p className="mt-1 text-sm text-zinc-500">Effective {EFFECTIVE}</p>

      <div className="prose prose-zinc mt-8 max-w-none text-sm leading-relaxed text-zinc-700">
        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">1. Who we are</h2>
          <p>
            Photoboot is operated by <strong>Blocktech Ventures LLC</strong>{" "}
            (&ldquo;we&rdquo;, &ldquo;us&rdquo;). Photoboot is a photo-booth
            experience used at private events. After a guest poses for photos
            at the booth, they may optionally provide an email address or
            phone number to receive a link to their photo.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">2. SMS messaging program</h2>
          <p>
            By entering your phone number on the booth, you consent to receive
            one (1) text message from Photoboot containing a link to your
            photo. We will not send promotional, marketing, or unrelated
            messages. Message and data rates may apply depending on your
            carrier and plan.
          </p>
          <p>
            <strong>Opting out:</strong> Reply <strong>STOP</strong> to any
            message to immediately opt out of further messages. Reply{" "}
            <strong>HELP</strong> for help, or contact us at the address below.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">3. Eligibility</h2>
          <p>
            You must be 18 or older, or have permission from a parent or
            guardian, to provide your phone number or email at the booth.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">4. Acceptable use</h2>
          <p>
            Photos captured at the booth are intended for personal,
            non-commercial use by event attendees. You agree not to use the
            service to harass, impersonate, or harm any other person.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">5. Disclaimers</h2>
          <p>
            The service is provided &ldquo;as is&rdquo; without warranties of
            any kind. We do not guarantee message delivery, retention beyond
            the event window, or specific availability of any feature.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">6. Changes</h2>
          <p>
            We may update these terms. Material changes will be reflected by
            updating the &ldquo;Effective&rdquo; date above.
          </p>
        </section>

        <section>
          <h2 className="mt-6 text-lg font-semibold text-zinc-900">7. Contact</h2>
          <p>
            Questions or opt-out requests: <a href="mailto:hello@blocktech.ventures" className="text-ig-pink underline">hello@blocktech.ventures</a>
          </p>
        </section>
      </div>

      <p className="mt-12 text-xs text-zinc-400">
        © Blocktech Ventures LLC · See also our{" "}
        <Link href="/privacy" className="underline">Privacy Policy</Link>.
      </p>
    </main>
  );
}
