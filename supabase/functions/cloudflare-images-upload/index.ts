// Supabase Edge Function: cloudflare-images-upload
// Secure proxy for Cloudflare Images uploads (never exposes API token to browser)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  // Support x-admin-token header (we may pass admin JWT there to avoid gateway JWT validation issues)
  "Access-Control-Allow-Headers": "authorization, x-admin-token, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const cfAccountId = Deno.env.get("CLOUDFLARE_ACCOUNT_ID")!;
    const cfApiToken = Deno.env.get("CLOUDFLARE_IMAGES_API_TOKEN")!;

    // Verify admin authentication
    // Prefer x-admin-token (workaround for some gateway JWT validation incompatibilities)
    const adminHeader = req.headers.get("x-admin-token") || req.headers.get("X-Admin-Token");
    const authHeader = req.headers.get("Authorization");

    const tokenSource = adminHeader || authHeader;
    if (!tokenSource) {
      return errorResponse("Unauthorized", 401);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Verify the JWT token (Supabase Auth validates it server-side)
    const token = tokenSource.replace("Bearer ", "").trim();
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return errorResponse("Unauthorized", 401);
    }

    // Check if user is admin
    const { data: adminRole } = await supabase
      .from("admin_roles")
      .select("role")
      .eq("user_id", user.id)
      .single();

    if (!adminRole) {
      return errorResponse("Forbidden - Admin access required", 403);
    }

    const body = await req.json();
    const { filename, contentType } = body;

    // ========================================
    // OPTION 1: Direct Upload URL (Recommended)
    // Creates a one-time upload URL that expires
    // ========================================

    // Try JSON first (official docs). Some accounts may require multipart/form-data.
    const directUploadUrl = `https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/images/v2/direct_upload`;

    let directUploadResult: any = null;

    // Attempt 1: JSON payload
    {
      const directUploadResponse = await fetch(directUploadUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${cfApiToken}`,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify({
          requireSignedURLs: false,
          metadata: {
            uploaded_by: user.id,
            filename: filename,
          },
        }),
      });

      directUploadResult = await directUploadResponse.json().catch(() => null);
    }

    // Attempt 2 (fallback): multipart/form-data if Cloudflare complains (error 5415)
    if (!directUploadResult?.success) {
      const errs = Array.isArray(directUploadResult?.errors) ? directUploadResult.errors : [];
      const needsForm = errs.some((e: any) => String(e?.code) === '5415');

      if (needsForm) {
        const fd = new FormData();
        fd.append('requireSignedURLs', 'false');
        fd.append('metadata', JSON.stringify({ uploaded_by: user.id, filename }));

        const resp2 = await fetch(directUploadUrl, {
          method: 'POST',
          headers: {
            // IMPORTANT: do NOT set Content-Type manually; let fetch set boundary.
            "Authorization": `Bearer ${cfApiToken}`,
            "Accept": "application/json",
          },
          body: fd as any,
        });

        directUploadResult = await resp2.json().catch(() => null);
      }
    }

    if (!directUploadResult?.success) {
      console.error("Cloudflare error:", directUploadResult);
      const msg =
        directUploadResult?.errors?.[0]?.message ||
        directUploadResult?.message ||
        "Failed to create upload URL";
      // Return a safe error (no secrets) to help debugging.
      return errorResponse(`Cloudflare Images: ${msg}`, 500);
    }

    // Log the action for audit
    await supabase.from("audit_logs").insert({
      user_id: user.id,
      action: "create_image_upload_url",
      details: { filename },
    });

    return new Response(
      JSON.stringify({
        success: true,
        uploadURL: directUploadResult.result.uploadURL,
        imageId: directUploadResult.result.id,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Upload URL error:", error);
    return errorResponse("Internal server error", 500);
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

// ========================================
// ALTERNATIVE: Server-side proxy upload
// Use this if you need to process images before uploading
// ========================================

/*
async function proxyUpload(req: Request) {
  const cfAccountId = Deno.env.get("CLOUDFLARE_ACCOUNT_ID")!;
  const cfApiToken = Deno.env.get("CLOUDFLARE_IMAGES_API_TOKEN")!;

  // Get the file from the request
  const formData = await req.formData();
  const file = formData.get("file") as File;

  if (!file) {
    return errorResponse("No file provided", 400);
  }

  // Validate file type
  const allowedTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
  if (!allowedTypes.includes(file.type)) {
    return errorResponse("Invalid file type", 400);
  }

  // Validate file size (max 10MB)
  if (file.size > 10 * 1024 * 1024) {
    return errorResponse("File too large", 400);
  }

  // Create form data for Cloudflare
  const cfFormData = new FormData();
  cfFormData.append("file", file);

  // Upload to Cloudflare Images
  const uploadResponse = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/images/v1`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${cfApiToken}`,
      },
      body: cfFormData,
    }
  );

  const uploadResult = await uploadResponse.json();

  if (!uploadResult.success) {
    console.error("Cloudflare upload error:", uploadResult);
    return errorResponse("Upload failed", 500);
  }

  return new Response(
    JSON.stringify({
      success: true,
      imageId: uploadResult.result.id,
      variants: uploadResult.result.variants,
    }),
    {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    }
  );
}
*/
