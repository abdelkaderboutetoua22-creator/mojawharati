// Supabase Edge Function: get-order-public
// Returns limited order details to customer using (order_id + public_token).
// Uses service role on DB side; does NOT expose any secrets.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const body = await req.json().catch(() => ({}));
    const order_id = String(body.order_id || "").trim();
    const public_token = String(body.public_token || "").trim();

    if (!order_id || !public_token) {
      return json({ success: false, error: "Missing order_id or public_token" }, 400);
    }

    // Fetch order and items
    const { data: order, error: orderErr } = await supabase
      .from("orders")
      .select("id,created_at,full_name,phone,wilaya,commune,address,delivery_type,note,subtotal,shipping,total,status,public_token,event_id")
      .eq("id", order_id)
      .eq("public_token", public_token)
      .single();

    if (orderErr || !order) {
      return json({ success: false, error: "Not found" }, 404);
    }

    const { data: items } = await supabase
      .from("order_items")
      .select("product_id,product_name,price,quantity,selected_size,selected_color,options")
      .eq("order_id", order.id);

    // Try to attach first product image
    const productIds = (items || []).map((it) => it.product_id).filter(Boolean);
    let productsById: Record<string, any> = {};
    if (productIds.length) {
      const { data: prods } = await supabase
        .from("products")
        .select("id,images")
        .in("id", productIds);
      (prods || []).forEach((p) => { productsById[p.id] = p; });
    }

    const enriched = (items || []).map((it) => ({
      ...it,
      image: productsById[it.product_id]?.images?.[0] || null,
    }));

    return json({ success: true, order, items: enriched });
  } catch (e) {
    console.error("get-order-public error:", e);
    return json({ success: false, error: "Unexpected error" }, 500);
  }
});

function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
