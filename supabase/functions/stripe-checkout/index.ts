import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PLANS = {
  starter: { name: "WodIO Starter", amount: 2900 },
  pro: { name: "WodIO Pro", amount: 4900 },
  elite: { name: "WodIO Elite", amount: 7900 },
} as const;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  try {
    const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecret) throw new Error("STRIPE_SECRET_KEY_not_configured");
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "authentication_required" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { autoRefreshToken: false, persistSession: false } });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: userData, error: userError } = await authClient.auth.getUser();
    const user = userData?.user;
    if (userError || !user) return new Response(JSON.stringify({ error: "invalid_session" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const body = await req.json();
    const plan = String(body?.plan || "").toLowerCase() as keyof typeof PLANS;
    const selected = PLANS[plan];
    if (!selected) return new Response(JSON.stringify({ error: "invalid_plan" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const { data: profile } = await adminClient.from("profiles").select("box_id").eq("id", user.id).single();
    if (!profile?.box_id) throw new Error("box_not_found");
    const { data: box } = await adminClient.from("boxes").select("id,name,contact_email,status,subscription_plan").eq("id", profile.box_id).single();
    if (!box || box.subscription_plan !== plan || box.status !== "pending_payment") throw new Error("box_not_pending_payment");

    const origin = new URL(req.url).origin;
    const successUrl = body?.success_url || `${origin}/stripe-success.html?session_id={CHECKOUT_SESSION_ID}`;
    const cancelUrl = body?.cancel_url || `${origin}/create-box.html?plan=${plan}&payment=cancelled`;

    const params = new URLSearchParams();
    params.set("mode", "subscription");
    params.set("customer_email", user.email || box.contact_email);
    params.set("success_url", successUrl);
    params.set("cancel_url", cancelUrl);
    params.set("line_items[0][price_data][currency]", "eur");
    params.set("line_items[0][price_data][unit_amount]", String(selected.amount));
    params.set("line_items[0][price_data][recurring][interval]", "month");
    params.set("line_items[0][price_data][product_data][name]", selected.name);
    params.set("line_items[0][quantity]", "1");
    params.set("metadata[box_id]", box.id);
    params.set("metadata[plan]", plan);
    params.set("subscription_data[metadata][box_id]", box.id);
    params.set("subscription_data[metadata][plan]", plan);
    params.set("billing_address_collection", "required");
    params.set("allow_promotion_codes", "true");

    const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeSecret}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    });
    const session = await response.json();
    if (!response.ok) throw new Error(session?.error?.message || "stripe_checkout_failed");

    await adminClient.from("boxes").update({ stripe_checkout_session_id: session.id, subscription_status: "pending_payment", updated_at: new Date().toISOString() }).eq("id", box.id);
    return new Response(JSON.stringify({ url: session.url, session_id: session.id }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    return new Response(JSON.stringify({ error: message }), { status: message === "STRIPE_SECRET_KEY_not_configured" ? 503 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
