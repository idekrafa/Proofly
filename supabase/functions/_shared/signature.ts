const textEncoder = new TextEncoder();

export type SignatureManifest = {
  appVersion: string;
  caseID: string;
  exportID: string | null;
  includeStatementPlaceholder: boolean;
  issuedAt: string;
  keyVersion: string;
  nonce: string;
  pdfExportMode: string;
  signatureImageSHA256: string;
  signaturePage: string;
  signaturePlacement: string;
  signedAt: string;
  sourcePDFSHA256: string | null;
  userID: string;
};

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

export function configuredKeyVersion(): string {
  return Deno.env.get("PROOFKIT_SIGNATURE_KEY_VERSION")?.trim() || "v1";
}

/// Public authenticity page. The marketing domain rewrites `/verify` to the
/// `verify-signature-token` Edge Function, which serves HTML to browsers.
const DEFAULT_VERIFICATION_BASE_URL = "https://www.proofly.me/verify";

export function configuredVerificationBaseURL(): string {
  return Deno.env.get("PROOFKIT_SIGNATURE_VERIFICATION_BASE_URL")?.trim() || DEFAULT_VERIFICATION_BASE_URL;
}

export function isSHA256Hex(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value.trim());
}

export function requiredString(value: unknown, field: string, maxLength = 256): string {
  if (typeof value !== "string") throw new Error(`${field}_required`);
  const cleaned = value.trim();
  if (!cleaned) throw new Error(`${field}_required`);
  if (cleaned.length > maxLength) throw new Error(`${field}_too_long`);
  return cleaned;
}

export function optionalUUID(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  const cleaned = requiredString(value, field, 64);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(cleaned)) {
    throw new Error(`${field}_invalid`);
  }
  return cleaned;
}

export function parseDate(value: unknown, field: string): string {
  const cleaned = requiredString(value, field, 64);
  const date = new Date(cleaned);
  if (Number.isNaN(date.getTime())) throw new Error(`${field}_invalid`);
  return date.toISOString();
}

export function canonicalJSONString(value: unknown): string {
  return JSON.stringify(sortCanonical(value));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export async function signManifest(manifestJSON: string): Promise<string> {
  const keyBytes = secretBytes("PROOFKIT_SIGNATURE_HMAC_KEY");
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, textEncoder.encode(manifestJSON));
  return bytesToHex(new Uint8Array(signature));
}

export async function encryptManifest(manifestJSON: string): Promise<string> {
  const keyBytes = secretBytes("PROOFKIT_SIGNATURE_ENCRYPTION_KEY_B64", 32);
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    textEncoder.encode(manifestJSON),
  );
  return base64URL(concatBytes(iv, new Uint8Array(encrypted)));
}

export async function makeValidationToken(manifestJSON: string): Promise<string> {
  const randomBytes = crypto.getRandomValues(new Uint8Array(16));
  const digest = await sha256Hex(`${manifestJSON}.${bytesToHex(randomBytes)}`);
  const characters = digest.toUpperCase().slice(0, 20);
  return `PK-SIG-${characters.match(/.{1,4}/g)?.join("-") ?? characters}`;
}

export function publicVerificationURL(token: string): string {
  const baseURL = configuredVerificationBaseURL();
  const separator = baseURL.includes("?") ? "&" : "?";
  return `${baseURL}${separator}token=${encodeURIComponent(token)}`;
}

function secretBytes(name: string, expectedLength?: number): Uint8Array {
  const value = requiredEnv(name);
  const bytes = name.endsWith("_B64") ? base64ToBytes(value) : textEncoder.encode(value);
  if (expectedLength && bytes.byteLength !== expectedLength) {
    throw new Error(`${name} must decode to ${expectedLength} bytes`);
  }
  return bytes;
}

function sortCanonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortCanonical);
  if (value && typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      sorted[key] = sortCanonical((value as Record<string, unknown>)[key]);
    }
    return sorted;
  }
  return value;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function base64URL(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(`${normalized}${padding}`);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function concatBytes(lhs: Uint8Array, rhs: Uint8Array): Uint8Array {
  const output = new Uint8Array(lhs.byteLength + rhs.byteLength);
  output.set(lhs, 0);
  output.set(rhs, lhs.byteLength);
  return output;
}
