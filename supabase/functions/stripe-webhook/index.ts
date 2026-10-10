import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const encoder = new TextEncoder();

function hexToBytes(hex: string) {
  const bytes = new Uint8Array(Math.floor(hex.length / 2));
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

function equalBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function verify(payload: string, header: string, secret: string) {
  const timestamp = header.split(",").find(p => p.startsWith("t="))?.slice(2);
  const signatures = header.split(",").filter(p => p.startsWith("v1=")).map(p => p.slice(3));
  if (!timestamp || !signatures.length) return false;
  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > 300) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${payload}`)));
  return signatures.some(sig => equalBytes(digest, hexToBytes(sig)));
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    if (!secret) return json({ error: "STRIPE_WEBHOOK_SECRET_not_configured" }, 503);
    const signature = req.headers.get("stripe-signature");
    const payload = await req.text();
    if (!signature || !(await verify(payload, signature, secret))) return json({ error: "invalid_signature" }, 400);

    const event = JSON.parse(payload);
    const object = event?.data?.object || {};
    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { autoRefreshToken: false, persistSession: false } });

    const boxId = object?.metadata?.box_id || null;
    const plan = object?.metadata?.plan || null;
    const paymentId = object?.metadata?.payment_id || object?.payment_intent_data?.metadata?.payment_id || null;
    if (event.type === "account.updated" && event.account) {
      const account = object;
      const status = account.charges_enabled && account.payouts_enabled ? "connected" : account.details_submitted ? "restricted" : "pending";
      await adminClient.from("boxes").update({
        stripe_connect_status: status,
        stripe_connect_charges_enabled: !!account.charges_enabled,
        stripe_connect_payouts_enabled: !!account.payouts_enabled,
        stripe_connect_details_submitted: !!account.details_submitted,
        stripe_connect_updated_at: new Date().toISOString(),
      }).eq("stripe_account_id", event.account);
      return json({ received: true });
    }
    if (paymentId && event.type === "checkout.session.completed") {
      const paid = object.payment_status === "paid";
      await adminClient.from("payments").update({
        status: paid ? "paid" : "pending",
        payment_method: "card",
        provider: "stripe",
        provider_reference: object.id || undefined,
        paid_at: paid ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      }).eq("id", paymentId).eq("box_id", boxId || "");
      if (paid) {
        await adminClient.from("event_registrations").update({status:"registered",updated_at:new Date().toISOString()}).eq("payment_id",paymentId);
        const { data: tariffPayment } = await adminClient.from("payments")
          .select("id,user_id,box_id,tariff_id").eq("id", paymentId).eq("box_id", boxId || "").maybeSingle();
        if (tariffPayment?.tariff_id) {
          const { data: tariff } = await adminClient.from("box_tariffs")
            .select("id,name,tariff_type,price_cents,is_active").eq("id", tariffPayment.tariff_id).eq("box_id", tariffPayment.box_id).maybeSingle();
          if (tariff?.is_active && tariff.tariff_type === "monthly") {
            await adminClient.from("profiles").update({ tariff_id: tariff.id, updated_at: new Date().toISOString() }).eq("id", tariffPayment.user_id).eq("box_id", tariffPayment.box_id);
            const { data: schedules } = await adminClient.from("recurring_payment_schedules")
              .select("id").eq("box_id", tariffPayment.box_id).eq("user_id", tariffPayment.user_id).eq("category", "tariff").eq("active", true).order("created_at", { ascending: true });
            const nextMonth = new Date();
            nextMonth.setUTCMonth(nextMonth.getUTCMonth() + 1, 1);
            const nextRunDate = nextMonth.toISOString().slice(0, 10);
            const schedulePayload = {
              box_id: tariffPayment.box_id, user_id: tariffPayment.user_id, tariff_id: tariff.id,
              concept: "Tarifa · " + tariff.name, amount_cents: tariff.price_cents, currency: "EUR",
              due_day: 1, category: "tariff", active: true, next_run_date: nextRunDate, updated_at: new Date().toISOString(),
            };
            if (schedules?.length) {
              await adminClient.from("recurring_payment_schedules").update(schedulePayload).eq("id", schedules[0].id);
              if (schedules.length > 1) await adminClient.from("recurring_payment_schedules").update({ active: false, updated_at: new Date().toISOString() }).in("id", schedules.slice(1).map((s: {id:string}) => s.id));
            } else {
              await adminClient.from("recurring_payment_schedules").insert(schedulePayload);
            }
          }
        }
      }
      return json({ received: true });
    }
    if (!boxId) return json({ received: true });

    if (event.type === "checkout.session.completed") {
      const paid = object.payment_status === "paid";
      await adminClient.from("boxes").update({
        status: paid ? "active" : "pending_payment",
        subscription_status: paid ? "active" : "incomplete",
        subscription_plan: plan || undefined,
        stripe_customer_id: typeof object.customer === "string" ? object.customer : undefined,
        stripe_subscription_id: typeof object.subscription === "string" ? object.subscription : undefined,
        stripe_checkout_session_id: object.id || undefined,
        updated_at: new Date().toISOString(),
      }).eq("id", boxId);
      return json({ received: true });
    }

    if (["customer.subscription.created","customer.subscription.updated","customer.subscription.deleted"].includes(event.type)) {
      const status = String(object.status || "");
      const active = status === "active" || status === "trialing";
      const cancelled = event.type === "customer.subscription.deleted" || status === "canceled";
      const pending = status === "incomplete" || status === "incomplete_expired";
      await adminClient.from("boxes").update({
        status: active ? "active" : cancelled ? "suspended" : pending ? "pending_payment" : "suspended",
        subscription_status: cancelled ? "canceled" : status || "unpaid",
        stripe_customer_id: typeof object.customer === "string" ? object.customer : undefined,
        stripe_subscription_id: object.id || undefined,
        subscription_plan: plan || undefined,
        updated_at: new Date().toISOString(),
      }).eq("id", boxId);
      return json({ received: true });
    }

    return json({ received: true });
  } catch (error) {
    console.error("[stripe-webhook]", error);
    return json({ error: "webhook_processing_failed" }, 500);
  }
});
