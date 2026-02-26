/**
 * Authentication utilities for Edge Functions
 * JWT verification, user extraction, and request signature validation
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

/**
 * Extract and verify user from Authorization header
 * Returns user object or throws error
 */
export async function authenticateUser(req: Request) {
  const authHeader = req.headers.get("Authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new Error("Missing or invalid Authorization header");
  }

  const token = authHeader.replace("Bearer ", "");

  // Create Supabase client with anon key to verify token
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Missing Supabase configuration");
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // Verify token and get user
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new Error("Invalid or expired token");
  }

  return user;
}

/**
 * Verify HMAC signature from request headers
 * Format: X-Request-Signature: timestamp:signature
 */
export async function verifyRequestSignature(
  req: Request,
  userId: string,
  endpoint: string
): Promise<boolean> {
  const signatureHeader = req.headers.get("X-Request-Signature");

  if (!signatureHeader) {
    return false;
  }

  const [timestampStr, clientSignature] = signatureHeader.split(":");

  if (!timestampStr || !clientSignature) {
    return false;
  }

  const timestamp = parseInt(timestampStr, 10);

  // Check timestamp is recent (within 5 minutes)
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > 300) {
    console.log("Signature timestamp too old or in future");
    return false;
  }

  // Get access token from Authorization header
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return false;
  }

  const accessToken = authHeader.replace("Bearer ", "");

  // Recreate signature
  const message = `${userId}:${endpoint}:${timestamp}`;
  const hmacSecret = Deno.env.get("HMAC_SECRET");

  if (!hmacSecret) {
    throw new Error("Missing HMAC_SECRET");
  }

  const encoder = new TextEncoder();
  const keyData = encoder.encode(hmacSecret);
  const messageData = encoder.encode(message);

  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, messageData);
  const signatureHex = Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return signatureHex === clientSignature;
}

/**
 * CORS headers for Edge Functions
 */
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-request-signature",
};

/**
 * Handle OPTIONS request (CORS preflight)
 */
export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

/**
 * JSON response helper
 */
export function jsonResponse(
  data: any,
  status: number = 200,
  headers: Record<string, string> = {}
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
      ...headers,
    },
  });
}

/**
 * Error response helper
 */
export function errorResponse(
  message: string,
  status: number = 400,
  code?: string
): Response {
  return jsonResponse(
    {
      error: message,
      code: code || "error",
    },
    status
  );
}

/**
 * Extract client IP from request (for geolocation/abuse detection)
 */
export function getClientIp(req: Request): string | null {
  // Try various headers (depends on deployment)
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    return forwarded.split(",")[0].trim();
  }

  const realIp = req.headers.get("x-real-ip");
  if (realIp) {
    return realIp;
  }

  return null;
}
