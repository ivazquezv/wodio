import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Payload = {
  name?: string;
  contact_email?: string;
  phone?: string | null;
  address?: string | null;
  city?: string | null;
  postal_code?: string | null;
  tax_id?: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "authentication_required" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userError } = await authClient.auth.getUser();
    const user = userData?.user;

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "invalid_session" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = (await req.json()) as Payload;
    const name = payload.name?.trim();
    const contactEmail = payload.contact_email?.trim().toLowerCase();

    if (!name) {
      return new Response(JSON.stringify({ error: "box_name_required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!contactEmail) {
      return new Response(JSON.stringify({ error: "contact_email_required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("id, role, box_id")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "profile_not_found" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (profile.box_id) {
      const { data: currentBox } = await adminClient
        .from("boxes")
        .select("slug")
        .eq("id", profile.box_id)
        .maybeSingle();

      const canMigrateDemo =
        currentBox?.slug === "wodio-demo" && profile.role === "athlete";

      if (!canMigrateDemo) {
        return new Response(JSON.stringify({ error: "user_already_has_box" }), {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const baseSlug = name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 70) || "box";

    const slug = `${baseSlug}-${user.id.replaceAll("-", "").slice(0, 8)}`;

    const { data: box, error: boxError } = await adminClient
      .from("boxes")
      .insert({
        name,
        slug,
        contact_email: contactEmail,
        phone: payload.phone?.trim() || null,
        address: payload.address?.trim() || null,
        city: payload.city?.trim() || null,
        postal_code: payload.postal_code?.trim() || null,
        tax_id: payload.tax_id?.trim() || null,
        owner_id: user.id,
        status: "trial",
      })
      .select("id")
      .single();

    if (boxError || !box) {
      return new Response(JSON.stringify({ error: boxError?.message || "box_creation_failed" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: updateError } = await adminClient
      .from("profiles")
      .update({
        box_id: box.id,
        role: "box_admin",
        updated_at: new Date().toISOString(),
      })
      .eq("id", user.id);

    if (updateError) {
      await adminClient.from("boxes").delete().eq("id", box.id);
      return new Response(JSON.stringify({ error: "profile_update_failed" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, box_id: box.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : "unexpected_error",
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
