// Supabase Edge Function: meta-server-events
// Handles server-side Meta Conversions API tracking

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface TrackingEvent {
  event_name: string;
  event_id: string;
  phone?: string;
  value?: number;
  currency?: string;
  order_id?: string;
  content_ids?: string[];
  user_data?: {
    client_ip_address?: string;
    client_user_agent?: string;
    fbc?: string;
    fbp?: string;
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const metaPixelId = Deno.env.get("META_PIXEL_ID");
    const metaAccessToken = Deno.env.get("META_ACCESS_TOKEN");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!metaPixelId || !metaAccessToken) {
      console.log("Meta tracking not configured");
      return new Response(
        JSON.stringify({ success: true, message: "Tracking skipped - not configured" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const body: TrackingEvent = await req.json();

    // Check if purchase event should be sent based on settings
    if (body.event_name === "Purchase" && body.order_id) {
      const { data: settings } = await supabase
        .from("settings")
        .select("value")
        .eq("key", "purchase_event")
        .single();

      const purchaseEventTrigger = settings?.value || "confirmed";

      // If setting is "delivered", we shouldn't send now (will be sent later)
      // This function is called at order creation, so we check if immediate send is needed
      if (purchaseEventTrigger === "delivered") {
        // Store the event for later sending
        await supabase.from("pending_tracking_events").insert({
          order_id: body.order_id,
          event_name: body.event_name,
          event_id: body.event_id,
          event_data: body,
          trigger_status: "delivered",
        }).catch(() => {
          // Table might not exist, that's okay
        });

        return new Response(
          JSON.stringify({ success: true, message: "Event queued for delivery status" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Prepare user data with hashed PII
    const userData: Record<string, string> = {};

    // Hash phone number for Meta (SHA256)
    if (body.phone) {
      // Normalize phone: remove leading 0, add country code
      const normalizedPhone = "213" + body.phone.substring(1);
      userData.ph = await hashSHA256(normalizedPhone);
    }

    // Add other user data if provided
    if (body.user_data?.client_ip_address) {
      userData.client_ip_address = body.user_data.client_ip_address;
    }
    if (body.user_data?.client_user_agent) {
      userData.client_user_agent = body.user_data.client_user_agent;
    }
    if (body.user_data?.fbc) {
      userData.fbc = body.user_data.fbc;
    }
    if (body.user_data?.fbp) {
      userData.fbp = body.user_data.fbp;
    }

    // Build event payload
    const eventTime = Math.floor(Date.now() / 1000);
    const eventPayload = {
      data: [
        {
          event_name: body.event_name,
          event_time: eventTime,
          event_id: body.event_id, // For deduplication with client-side pixel
          action_source: "website",
          user_data: userData,
          custom_data: {
            value: body.value,
            currency: body.currency || "DZD",
            content_ids: body.content_ids,
            content_type: "product",
          },
        },
      ],
    };

    // Send to Meta Conversions API
    const metaResponse = await fetch(
      `https://graph.facebook.com/v18.0/${metaPixelId}/events?access_token=${metaAccessToken}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(eventPayload),
      }
    );

    const metaResult = await metaResponse.json();

    if (!metaResponse.ok) {
      console.error("Meta API Error:", metaResult);
      return new Response(
        JSON.stringify({ success: false, error: metaResult }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    console.log("Meta event sent successfully:", body.event_name, body.event_id);

    return new Response(
      JSON.stringify({ success: true, events_received: metaResult.events_received }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Tracking error:", error);
    return new Response(
      JSON.stringify({ success: false, error: "Tracking failed" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});

// SHA256 hash function
async function hashSHA256(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}
