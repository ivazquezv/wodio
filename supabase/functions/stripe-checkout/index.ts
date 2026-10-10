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
    let paymentId = String(body?.payment_id || "").trim();
    const tariffId = String(body?.tariff_id || "").trim();

    if (!paymentId && tariffId) {
      const { data: profile, error: profileError } = await adminClient.from("profiles").select("box_id,role").eq("id", user.id).single();
      if (profileError || !profile?.box_id || profile.role !== "athlete") throw new Error("athlete_profile_required");
      const { data: tariff, error: tariffError } = await adminClient.from("box_tariffs")
        .select("id,box_id,name,tariff_type,price_cents,is_active")
        .eq("id", tariffId).eq("box_id", profile.box_id).eq("is_active", true).single();
      if (tariffError || !tariff) throw new Error("tariff_not_available");
      if (!Number.isInteger(Number(tariff.price_cents)) || Number(tariff.price_cents) <= 0) throw new Error("invalid_tariff_price");
      const { data: createdPayment, error: createPaymentError } = await adminClient.from("payments").insert({
        user_id: user.id,
        box_id: profile.box_id,
        tariff_id: tariff.id,
        category: "tariff",
        concept: "Tarifa · " + tariff.name + (tariff.tariff_type === "monthly" ? " (mensual)" : " (pago único)"),
        amount_cents: tariff.price_cents,
        currency: "EUR",
        status: "pending",
        due_date: new Date().toISOString().slice(0, 10),
        payment_method: "card",
      }).select("id").single();
      if (createPaymentError || !createdPayment) throw new Error("tariff_payment_creation_failed");
      paymentId = createdPayment.id;
    }

    if (paymentId) {
      const { data: payment, error: paymentError } = await adminClient
        .from("payments")
        .select("id,user_id,box_id,concept,amount_cents,currency,status,tariff_id")
        .eq("id", paymentId)
        .single();
      if (paymentError || !payment) throw new Error("payment_not_found");
      if (payment.user_id !== user.id) throw new Error("payment_not_owned");
      if (payment.status !== "pending") throw new Error("payment_not_pending");
      if (!Number(payment.amount_cents) || Number(payment.amount_cents) <= 0) throw new Error("invalid_payment_amount");
      const { data: box, error: boxError } = await adminClient.from("boxes").select("id,stripe_account_id,stripe_connect_status,stripe_connect_charges_enabled").eq("id", payment.box_id).single();
      if (boxError || !box) throw new Error("box_not_found");
      if (!box.stripe_account_id) {
        const err = new Error("box_stripe_not_connected");
        (err as any).code = "box_stripe_not_connected";
        throw err;
      }

      const accountResponse = await fetch("https://api.stripe.com/v1/accounts/" + encodeURIComponent(box.stripe_account_id), {
        headers: { Authorization: `Bearer ${stripeSecret}` },
      });
      const account = await accountResponse.json();
      if (!accountResponse.ok) throw new Error(account?.error?.message || "stripe_account_lookup_failed");

      const connected = !!account.charges_enabled && !!account.payouts_enabled;
      await adminClient.from("boxes").update({
        stripe_connect_status: connected ? "connected" : account.details_submitted ? "restricted" : "pending",
        stripe_connect_charges_enabled: !!account.charges_enabled,
        stripe_connect_payouts_enabled: !!account.payouts_enabled,
        stripe_connect_details_submitted: !!account.details_submitted,
        stripe_connect_updated_at: new Date().toISOString(),
      }).eq("id", box.id);

      if (!connected) {
        const err = new Error("box_stripe_not_ready");
        (err as any).code = "box_stripe_not_ready";
        throw err;
      }

      const origin = new URL(req.url).origin;
      const successUrl = body?.success_url || origin + "/payments.html?payment=success&session_id={CHECKOUT_SESSION_ID}";
      const cancelUrl = body?.cancel_url || origin + "/payments.html?payment=cancelled";
      const params = new URLSearchParams();
      params.set("mode", "payment");
      params.set("customer_email", user.email || "");
      params.set("success_url", successUrl);
      params.set("cancel_url", cancelUrl);
      params.set("line_items[0][price_data][currency]", String(payment.currency || "EUR").toLowerCase());
      params.set("line_items[0][price_data][unit_amount]", String(payment.amount_cents));
      params.set("line_items[0][price_data][product_data][name]", payment.concept || "Pago WodIO");
      params.set("line_items[0][quantity]", "1");
      params.set("metadata[payment_id]", payment.id);
      params.set("metadata[box_id]", payment.box_id);
      params.set("metadata[user_id]", payment.user_id);
      if (payment.tariff_id) params.set("metadata[tariff_id]", payment.tariff_id);
      params.set("payment_intent_data[metadata][payment_id]", payment.id);
      params.set("payment_intent_data[metadata][box_id]", payment.box_id);
      params.set("payment_intent_data[metadata][user_id]", payment.user_id);
      if (payment.tariff_id) params.set("payment_intent_data[metadata][tariff_id]", payment.tariff_id);

      const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
        method: "POST",
        headers: { Authorization: `Bearer ${stripeSecret}`, "Stripe-Account": box.stripe_account_id, "Content-Type": "application/x-www-form-urlencoded" },
        body: params,
      });
      const session = await response.json();
      if (!response.ok) throw new Error(session?.error?.message || "stripe_checkout_failed");

      await adminClient.from("payments").update({
        provider: "stripe",
        provider_reference: session.id,
        updated_at: new Date().toISOString(),
      }).eq("id", payment.id).eq("user_id", user.id);

      return new Response(JSON.stringify({ url: session.url, session_id: session.id, payment_id: payment.id }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

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
    const code = (error as any)?.code || message;
    const friendly = code === "athlete_profile_required"
      ? "Esta cuenta no tiene un perfil de atleta asociado a un box. Accede con una cuenta de atleta o pide al administrador que revise el perfil."
      : code === "box_stripe_not_connected"
      ? "El box todavía no tiene Stripe conectado. El administrador debe completar la conexión de Stripe antes de cobrar."
      : code === "box_stripe_not_ready"
        ? "La cuenta de Stripe del box todavía está en configuración o verificación. El administrador debe completar los datos pendientes en Stripe."
        : message;
    const status = message === "STRIPE_SECRET_KEY_not_configured" ? 503 : code === "box_stripe_not_connected" || code === "box_stripe_not_ready" ? 409 : 400;
    return new Response(JSON.stringify({ ok: false, error: friendly, error_code: code }), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
