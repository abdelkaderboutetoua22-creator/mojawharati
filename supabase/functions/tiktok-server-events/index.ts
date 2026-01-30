// Supabase Edge Function: tiktok-server-events
// Sends server-side TikTok Events API (Pixel) events.
// Security model:
// - Accept calls from service role (create-order) OR authenticated admin (via x-admin-token)
// - TikTok Access Token stored as Supabase secret (never in client)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-admin-token, x-client-info, apikey, content-type",
};

interface TikTokEventRequest {
  event_name: string; // ViewContent, AddToCart, InitiateCheckout, Purchase
  event_id: string;
  phone?: string;
  value?: number;
  currency?: string;
  order_id?: string;
  content_ids?: string[];
  content_name?: string;
  contents?: Array<{ content_id: string; quantity?: number; price?: number; content_name?: string }>;
  // When called from admin after status update
  force_send?: boolean;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const tiktokAccessToken = Deno.env.get("TIKTOK_ACCESS_TOKEN") || "";
    const tiktokPixelId = Deno.env.get("TIKTOK_PIXEL_ID") || Deno.env.get("TIKTOK_PIXEL_CODE") || "";

    if (!tiktokAccessToken || !tiktokPixelId) {
      return json({ success: true, message: "TikTok tracking skipped - not configured" });
    }

    // AuthZ: allow service role calls OR admin token
    const authHeader = req.headers.get("Authorization") || "";
    const adminHeader = req.headers.get("x-admin-token") || req.headers.get("X-Admin-Token") || "";

    const supabase = createClient(supabaseUrl, serviceKey);

    const isServiceCall = authHeader.replace("Bearer ", "").trim() === serviceKey;

    if (!isServiceCall) {
      // verify admin JWT
      const token = (adminHeader || authHeader).replace("Bearer ", "").trim();
      if (!token) return json({ success: false, error: "Unauthorized" }, 401);

      const { data: { user }, error: userErr } = await supabase.auth.getUser(token);
      if (userErr || !user) return json({ success: false, error: "Unauthorized" }, 401);

      const { data: adminRole } = await supabase
        .from("admin_roles")
        .select("role")
        .eq("user_id", user.id)
        .maybeSingle();

      if (!adminRole) return json({ success: false, error: "Forbidden" }, 403);
    }

    const body: TikTokEventRequest = await req.json();

    // COD purchase timing: if event is Purchase and order_id provided and not force_send,
    // check settings.purchase_event; if set to 'delivered' we don't send now.
    if (body.event_name === "Purchase" && body.order_id && !body.force_send) {
      const { data: s } = await supabase
        .from("settings")
        .select("value")
        .eq("key", "purchase_event")
        .maybeSingle();

      const trigger = s?.value || "confirmed";
      if (trigger === "delivered") {
        return json({ success: true, message: "Event skipped (purchase_event=delivered)" });
      }
    }

    const clientIP = req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for")?.split(",")[0] || "";
    const userAgent = req.headers.get("user-agent") || "";

    // Hash phone to SHA256 as per TikTok best practice.
    const user: Record<string, any> = {
      client_ip_address: clientIP,
      client_user_agent: userAgent,
    };

    if (body.phone) {
      const normalized = normalizeDzPhone(body.phone);
      if (normalized) user.phone = [await sha256(normalized)];
    }

    const eventTime = Math.floor(Date.now() / 1000);

    const payload = {
      pixel_code: tiktokPixelId,
      event: body.event_name,
      event_id: body.event_id,
      timestamp: eventTime,
      context: {
        user,
        page: {
          url: req.headers.get("referer") || "",
          referrer: req.headers.get("referer") || "",
        },
      },
      properties: {
        currency: body.currency || "DZD",
        value: body.value,
        content_type: "product",
        content_id: body.content_ids?.[0],
        contents: body.contents || (body.content_ids || []).map((id) => ({ content_id: id })),
        content_name: body.content_name,
        order_id: body.order_id,
      },
    };

    const resp = await fetch("https://business-api.tiktok.com/open_api/v1.3/pixel/track/", {
      method: "POST",
      headers: {
        "Access-Token": tiktokAccessToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await resp.json().catch(() => ({}));
    if (!resp.ok || data?.code) {
      // TikTok uses code=0 for success.
      const ok = data?.code === 0;
      if (!ok) {
        return json({ success: false, error: data?.message || "TikTok API error", details: data }, 500);
      }
    }

    return json({ success: true, tiktok: data });
  } catch (e) {
    console.error("tiktok-server-events error:", e);
    return json({ success: false, error: "Tracking failed" }, 500);
  }
});

function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeDzPhone(phone: string): string | null {
  const p = String(phone || "").trim();
  const m = p.match(/^0[567]\d{8}$/);
  if (!m) return null;
  // TikTok expects E164-like hashing without plus.
  return "213" + p.slice(1);
}

async function sha256(text: string): Promise<string> {
  const enc = new TextEncoder();
  const data = enc.encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
