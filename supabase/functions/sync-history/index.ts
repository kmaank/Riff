/**
 * sync-history Edge Function
 * Handles cloud sync of riff history across devices
 * POST: Upload history entries (batch or single)
 * GET: Download user's history
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
} from "../_shared/auth.ts";
import type {
  SyncHistoryUploadResponse,
  SyncHistoryDownloadResponse,
  RiffHistoryEntry,
} from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    const supabase = getSupabaseServiceClient();

    // GET: Download history
    if (req.method === "GET") {
      const url = new URL(req.url);
      const limit = parseInt(url.searchParams.get("limit") || "1000");
      const offset = parseInt(url.searchParams.get("offset") || "0");

      const { data: history, error } = await supabase.rpc("get_user_history", {
        p_user_id: userId,
        p_limit: Math.min(limit, 1000),
        p_offset: offset,
      });

      if (error) {
        console.error("get_user_history error:", error);
        return errorResponse("Failed to fetch history", 500);
      }

      const response: SyncHistoryDownloadResponse = {
        success: true,
        history: history || [],
        count: history?.length || 0,
      };

      return jsonResponse(response);
    }

    // POST: Upload history (single or batch)
    if (req.method === "POST") {
      const body = await req.json();

      // Batch upload
      if (body.entries && Array.isArray(body.entries)) {
        const { data, error } = await supabase.rpc("batch_upload_history", {
          p_user_id: userId,
          p_entries: body.entries,
        });

        if (error) {
          console.error("batch_upload_history error:", error);
          return errorResponse("Failed to upload history batch", 500);
        }

        return jsonResponse(data);
      }

      // Single entry upload
      const { timestamp, original, refined, style, script_mode, device_id } = body;

      if (!timestamp || !original || !refined || !style) {
        return errorResponse(
          "Missing required fields: timestamp, original, refined, style",
          400
        );
      }

      const { data, error } = await supabase.rpc("upload_riff_history", {
        p_user_id: userId,
        p_timestamp: timestamp,
        p_original: original,
        p_refined: refined,
        p_style: style,
        p_script_mode: script_mode || null,
        p_device_id: device_id || null,
      });

      if (error) {
        console.error("upload_riff_history error:", error);
        return errorResponse("Failed to upload history entry", 500);
      }

      return jsonResponse(data as SyncHistoryUploadResponse);
    }

    return errorResponse("Method not allowed", 405);
  } catch (error: any) {
    console.error("sync-history error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
