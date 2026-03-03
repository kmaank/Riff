// Edge Function: log-usage
// Logs a riff (usage tracking) after successful transcription

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { getSupabaseServiceClient, getUserId, corsHeaders } from '../_shared/clients.ts';

interface LogUsageRequest {
  word_count: number;
  recording_seconds: number;
  style?: string;
  script_mode?: string;
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const userId = await getUserId(req);

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const body: LogUsageRequest = await req.json();
    
    if (!body.word_count && !body.recording_seconds) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Insert usage log (service role required - RLS only allows service_role to INSERT)
    const supabase = getSupabaseServiceClient();
    const { data, error } = await supabase
      .from('usage_logs')
      .insert({
        user_id: userId,
        word_count: body.word_count || 0,
        recording_seconds: body.recording_seconds || 0,
        style: body.style,
        script_mode: body.script_mode,
      })
      .select()
      .single();

    if (error) {
      console.error('Error logging usage:', error);
      return new Response(
        JSON.stringify({ error: 'Failed to log usage', message: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, log_id: data.id }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in log-usage:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
