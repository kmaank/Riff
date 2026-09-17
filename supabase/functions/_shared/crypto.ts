// AES-256-GCM wrap for managed Groq keys.
// KEK never leaves the Edge Function environment.

const PREFIX = "v1.";

function getSecret(): string {
  const secret =
    Deno.env.get("API_KEY_WRAP_SECRET") ||
    Deno.env.get("ENCRYPTION_SECRET") ||
    "";
  if (!secret) {
    throw new Error("API_KEY_WRAP_SECRET / ENCRYPTION_SECRET is not set");
  }
  return secret;
}

async function getKek(): Promise<CryptoKey> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(getSecret()),
  );
  return crypto.subtle.importKey("raw", hash, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

function toB64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function fromB64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function isWrapped(value: string): boolean {
  return typeof value === "string" && value.startsWith(PREFIX);
}

export async function wrapApiKey(plaintext: string): Promise<string> {
  const key = await getKek();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const buf = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(plaintext),
  );
  return `${PREFIX}${toB64(iv)}.${toB64(new Uint8Array(buf))}`;
}

export async function unwrapApiKey(blob: string): Promise<string> {
  if (!isWrapped(blob)) {
    return blob;
  }
  const parts = blob.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") {
    throw new Error("Invalid wrapped key format");
  }
  const iv = fromB64(parts[1]);
  const data = fromB64(parts[2]);
  const key = await getKek();
  const buf = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    data,
  );
  return new TextDecoder().decode(buf);
}
