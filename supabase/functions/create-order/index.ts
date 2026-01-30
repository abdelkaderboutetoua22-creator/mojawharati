// Supabase Edge Function: create-order
// Handles secure order creation with validation, Turnstile verification, and rate limiting

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface OrderRequest {
  full_name: string;
  phone: string;
  wilaya: string;
  commune?: string;
  delivery_type: "office" | "home";
  address?: string;
  note?: string;
  cart_items: Array<{ product_id: string; quantity: number; options?: { size?: string; color?: string } | null }>;
  turnstile_token: string;
  event_id: string;
  cart_id?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const turnstileSecret = Deno.env.get("TURNSTILE_SECRET_KEY")!;

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get client IP
    const clientIP = req.headers.get("cf-connecting-ip") || 
                     req.headers.get("x-forwarded-for")?.split(",")[0] || 
                     "unknown";
    const userAgent = req.headers.get("user-agent") || "";

    // Parse request body
    const body: OrderRequest = await req.json();

    // ========================================
    // VALIDATION
    // ========================================

    // Required fields
    if (!body.full_name?.trim()) {
      return errorResponse("الاسم مطلوب", 400);
    }

    // Phone validation (Algerian format: 05/06/07 + 8 digits)
    const phoneRegex = /^0[567]\d{8}$/;
    if (!phoneRegex.test(body.phone)) {
      return errorResponse("رقم الهاتف غير صحيح", 400);
    }

    // Wilaya validation
    const { data: wilaya } = await supabase
      .from("wilayas")
      .select("code")
      .eq("code", body.wilaya)
      .single();

    if (!wilaya) {
      return errorResponse("الولاية غير موجودة", 400);
    }

    // Delivery type validation
    if (!["office", "home"].includes(body.delivery_type)) {
      return errorResponse("نوع التوصيل غير صحيح", 400);
    }

    // Address required for home delivery
    if (body.delivery_type === "home" && !body.address?.trim()) {
      return errorResponse("العنوان مطلوب للتوصيل المنزلي", 400);
    }

    // Cart items validation
    if (!body.cart_items?.length) {
      return errorResponse("السلة فارغة", 400);
    }

    // ========================================
    // TURNSTILE VERIFICATION
    // ========================================

    const turnstileResponse = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `secret=${turnstileSecret}&response=${body.turnstile_token}&remoteip=${clientIP}`,
      }
    );

    const turnstileResult = await turnstileResponse.json();

    if (!turnstileResult.success) {
      return errorResponse("فشل التحقق الأمني", 400);
    }

    // ========================================
    // RATE LIMITING
    // ========================================

    const now = new Date();
    const windowStart = new Date(now.getTime() - 60 * 60 * 1000); // 1 hour window

    // Check IP rate limit (max 10 orders per hour)
    const { data: ipRateLimit } = await supabase
      .from("rate_limits")
      .select("count")
      .eq("identifier", clientIP)
      .eq("identifier_type", "ip")
      .eq("action", "create_order")
      .gte("window_start", windowStart.toISOString())
      .single();

    if (ipRateLimit && ipRateLimit.count >= 10) {
      return errorResponse("تم تجاوز الحد المسموح من الطلبات", 429);
    }

    // Check phone rate limit (max 3 orders per hour)
    const { data: phoneRateLimit } = await supabase
      .from("rate_limits")
      .select("count")
      .eq("identifier", body.phone)
      .eq("identifier_type", "phone")
      .eq("action", "create_order")
      .gte("window_start", windowStart.toISOString())
      .single();

    if (phoneRateLimit && phoneRateLimit.count >= 3) {
      return errorResponse("تم تجاوز الحد المسموح من الطلبات لهذا الرقم", 429);
    }

    // ========================================
    // DUPLICATE DETECTION
    // ========================================

    // Check for duplicate order in last 5 minutes with same phone
    const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000);
    const { data: recentOrders } = await supabase
      .from("orders")
      .select("id")
      .eq("phone", body.phone)
      .gte("created_at", fiveMinutesAgo.toISOString());

    if (recentOrders && recentOrders.length > 0) {
      // Check if it's the same items
      const { data: recentItems } = await supabase
        .from("order_items")
        .select("product_id, quantity")
        .eq("order_id", recentOrders[0].id);

      const isDuplicate = recentItems?.length === body.cart_items.length &&
        body.cart_items.every(item =>
          recentItems.some(ri => ri.product_id === item.product_id && ri.quantity === item.quantity)
        );

      if (isDuplicate) {
        return errorResponse("هذا الطلب مسجل مسبقاً", 400);
      }
    }

    // ========================================
    // FETCH PRODUCTS AND CALCULATE PRICES (SERVER-SIDE)
    // ========================================

    const productIds = body.cart_items.map(item => item.product_id);
    const { data: products, error: productsError } = await supabase
      .from("products")
      .select("id, name, price, is_active")
      .in("id", productIds);

    if (productsError || !products?.length) {
      return errorResponse("خطأ في تحميل المنتجات", 500);
    }

    // Validate all products are active
    const inactiveProducts = products.filter(p => !p.is_active);
    if (inactiveProducts.length > 0) {
      return errorResponse("بعض المنتجات غير متاحة", 400);
    }

    // Calculate subtotal from DB prices (NEVER trust client prices)
    let subtotal = 0;
    const orderItems = body.cart_items.map(item => {
      const product = products.find(p => p.id === item.product_id);
      if (!product) throw new Error("Product not found");
      const lineTotal = product.price * item.quantity;
      subtotal += lineTotal;
      return {
        product_id: product.id,
        product_name: product.name,
        price: product.price,
        quantity: item.quantity,
      };
    });

    // ========================================
    // FETCH SHIPPING RATE (SERVER-SIDE)
    // ========================================

    const { data: shippingRate, error: shippingError } = await supabase
      .from("shipping_rates")
      .select("price, is_enabled")
      .eq("wilaya_code", body.wilaya)
      .eq("delivery_type", body.delivery_type)
      .single();

    if (shippingError || !shippingRate || !shippingRate.is_enabled) {
      return errorResponse("التوصيل غير متاح لهذه الولاية", 400);
    }

    const shipping = shippingRate.price;
    const total = subtotal + shipping;

    // ========================================
    // CREATE ORDER
    // ========================================

    const { data: order, error: orderError } = await supabase
      .from("orders")
      .insert({
        full_name: body.full_name.trim(),
        phone: body.phone,
        wilaya: body.wilaya,
        commune: body.commune?.trim() || null,
        address: body.address?.trim() || null,
        delivery_type: body.delivery_type,
        note: body.note?.trim() || null,
        subtotal,
        shipping,
        total,
        status: "new",
        ip_address: clientIP,
        user_agent: userAgent.substring(0, 500),
        event_id: body.event_id,
      })
      .select("id, public_token")
      .single();

    if (orderError) {
      console.error("Order creation error:", orderError);
      return errorResponse("خطأ في إنشاء الطلب", 500);
    }

    // Insert order items
    const orderItemsWithOrderId = orderItems.map(item => ({
      ...item,
      order_id: order.id,
    }));

    // Attach options if provided (backwards compatible)
    const optionsByProductId = new Map<string, { size?: string; color?: string } | null>();
    for (const ci of body.cart_items) {
      optionsByProductId.set(ci.product_id, ci.options || null);
    }

    const orderItemsWithOptions = orderItemsWithOrderId.map((it) => ({
      ...it,
      selected_size: optionsByProductId.get(it.product_id) ? optionsByProductId.get(it.product_id)?.size ?? null : null,
      selected_color: optionsByProductId.get(it.product_id) ? optionsByProductId.get(it.product_id)?.color ?? null : null,
      options: optionsByProductId.get(it.product_id) ?? null,
    }));

    const { error: itemsError } = await supabase
      .from("order_items")
      .insert(orderItemsWithOptions);

    if (itemsError) {
      console.error("Order items error:", itemsError);
      // Rollback order
      await supabase.from("orders").delete().eq("id", order.id);
      return errorResponse("خطأ في إنشاء الطلب", 500);
    }

    // Insert initial status history
    await supabase.from("order_status_history").insert({
      order_id: order.id,
      status: "new",
    });

    // ========================================
    // UPDATE RATE LIMITS
    // ========================================

    // Update IP rate limit
    if (ipRateLimit) {
      await supabase
        .from("rate_limits")
        .update({ count: ipRateLimit.count + 1 })
        .eq("identifier", clientIP)
        .eq("identifier_type", "ip")
        .eq("action", "create_order");
    } else {
      await supabase.from("rate_limits").insert({
        identifier: clientIP,
        identifier_type: "ip",
        action: "create_order",
        count: 1,
        window_start: now.toISOString(),
      });
    }

    // Update phone rate limit
    if (phoneRateLimit) {
      await supabase
        .from("rate_limits")
        .update({ count: phoneRateLimit.count + 1 })
        .eq("identifier", body.phone)
        .eq("identifier_type", "phone")
        .eq("action", "create_order");
    } else {
      await supabase.from("rate_limits").insert({
        identifier: body.phone,
        identifier_type: "phone",
        action: "create_order",
        count: 1,
        window_start: now.toISOString(),
      });
    }

    // ========================================
    // DELETE CART (if provided)
    // ========================================

    if (body.cart_id) {
      await supabase.from("carts").delete().eq("id", body.cart_id);
    }

    // ========================================
    // TRIGGER SERVER-SIDE TRACKING
    // ========================================

    // Call meta-server-events function asynchronously
    const trackingData = {
      event_name: "Purchase",
      event_id: body.event_id,
      phone: body.phone,
      value: total,
      currency: "DZD",
      order_id: order.id,
      content_ids: productIds,
    };

    // Fire and forget - don't wait for response
    fetch(`${supabaseUrl}/functions/v1/meta-server-events`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${supabaseServiceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(trackingData),
    }).catch(console.error);

    // TikTok server-side events (optional) - fire and forget
    const tiktokTrackingData = {
      event_name: "Purchase",
      event_id: body.event_id,
      phone: body.phone,
      value: total,
      currency: "DZD",
      order_id: order.id,
      content_ids: productIds,
      contents: orderItems.map((it) => ({
        content_id: it.product_id,
        quantity: it.quantity,
        price: it.price,
        content_name: it.product_name,
      })),
    };

    fetch(`${supabaseUrl}/functions/v1/tiktok-server-events`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${supabaseServiceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(tiktokTrackingData),
    }).catch(console.error);

    // ========================================
    // RETURN SUCCESS
    // ========================================

    return new Response(
      JSON.stringify({
        success: true,
        order_id: order.id,
        public_token: order.public_token,
        total,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return errorResponse("حدث خطأ غير متوقع", 500);
  }
});

function errorResponse(message: string, status: number) {
  return new Response(
    JSON.stringify({ success: false, error: message }),
    {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status,
    }
  );
}
