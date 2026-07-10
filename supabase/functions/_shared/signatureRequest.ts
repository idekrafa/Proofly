import { sha256Hex } from "./signature.ts";

export const SIGNATURE_REQUEST_BUCKET = "signature-requests";
export const MAX_PDF_BYTES = 15 * 1024 * 1024;
export const MAX_SIGNATURE_IMAGE_BYTES = 2 * 1024 * 1024;
export const DEFAULT_EXPIRY_DAYS = 7;
export const MAX_EXPIRY_DAYS = 30;

export type SignatureRequestRow = {
  id: string;
  user_id: string;
  case_id: string;
  source_export_id: string | null;
  request_token: string;
  status: string;
  document_title: string;
  requester_name: string | null;
  message: string | null;
  signature_page: string;
  signature_placement: string;
  pdf_storage_path: string;
  pdf_sha256: string;
  signer_name: string | null;
  signature_image_path: string | null;
  signature_image_sha256: string | null;
  signature_position_page: number | null;
  signature_position_x: number | null;
  signature_position_y: number | null;
  signed_at: string | null;
  expires_at: string;
  created_at: string;
};

export type SignaturePosition = {
  pageIndex: number;
  x: number;
  y: number;
};

/// Signer-chosen placement from the signing page: zero-based page index plus the
/// normalized center of the signature box (0...1, origin top-left) on that page.
export function parseSignaturePosition(value: unknown): SignaturePosition | null {
  if (value == null) return null;
  if (typeof value !== "object") throw new Error("signaturePosition_invalid");
  const record = value as Record<string, unknown>;
  const pageIndex = Number(record.pageIndex);
  const x = Number(record.x);
  const y = Number(record.y);
  if (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex > 9999) throw new Error("signaturePosition_invalid");
  if (!Number.isFinite(x) || x < 0 || x > 1) throw new Error("signaturePosition_invalid");
  if (!Number.isFinite(y) || y < 0 || y > 1) throw new Error("signaturePosition_invalid");
  return { pageIndex, x, y };
}

export function makeRequestToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return base64URL(bytes);
}

/// Share links open the static signing page hosted on the marketing domain
/// (source: website/sign/index.html; see docs/ask-sign-feature.md). That page calls
/// the `sign-request` Edge Function cross-origin for data (`format=json`), the PDF
/// (`asset=pdf`), and the signature submit — supabase.co cannot render HTML itself.
const DEFAULT_SIGN_REQUEST_BASE_URL = "https://www.proofly.me/sign";

export function signRequestPageURL(token: string): string {
  const base = Deno.env.get("PROOFKIT_SIGN_REQUEST_BASE_URL")?.trim() || DEFAULT_SIGN_REQUEST_BASE_URL;
  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}token=${encodeURIComponent(token)}`;
}

export async function tokenLookupHash(token: string): Promise<string> {
  return await sha256Hex(token);
}

export function isExpired(row: { expires_at: string }): boolean {
  const expiry = new Date(row.expires_at);
  return !Number.isNaN(expiry.getTime()) && expiry.getTime() < Date.now();
}

export function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/").replace(/\s/g, "");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(`${normalized}${padding}`);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export async function sha256HexOfBytes(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes.buffer as ArrayBuffer);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}

function base64URL(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}
