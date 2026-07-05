import crypto from "node:crypto";

export const SHARE_COOKIE_MAX_AGE = 60 * 60 * 24 * 30;

export function cookieName(shareCode: string): string {
  return `evt_share_${shareCode}`;
}

// HMAC binds the cookie to the current password hash — rotating the password
// invalidates every outstanding cookie for that share_code.
export function signShareCookie(shareCode: string, passwordHash: string): string {
  const secret = process.env.SHARE_COOKIE_SECRET;
  if (!secret) throw new Error("SHARE_COOKIE_SECRET not set");
  return crypto
    .createHmac("sha256", secret)
    .update(`${shareCode}|${passwordHash}`)
    .digest("base64url");
}

export function verifyShareCookie(
  shareCode: string,
  passwordHash: string | null,
  cookieValue: string,
): boolean {
  if (!passwordHash || !cookieValue) return false;
  let expected: string;
  try {
    expected = signShareCookie(shareCode, passwordHash);
  } catch {
    return false;
  }
  if (expected.length !== cookieValue.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(cookieValue));
}
