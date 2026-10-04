import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const C = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const out = (x:any, s=200) => new Response(JSON.stringify(x), {
  status: s,
  headers: {...C, "Content-Type": "application/json"}
});

async function stripe(path:string, p?:URLSearchParams, method="POST"){
  const k = Deno.env.get("STRIPE_SECRET_KEY");
  if(!k) throw Error("STRIPE_SECRET_KEY_not_configured");

  const r = await fetch("https://api.stripe.com" + path, {
    method,
    headers: {
      Authorization: "Bearer " + k,
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: method === "POST" ? p : undefined
  });

  const d = await r.json();
  if(!r.ok){
    const e:any = new Error(d?.error?.message || "stripe_request_failed");
    e.stripe_code = d?.error?.code || null;
    e.stripe_type = d?.error?.type || null;
    throw e;
  }
  return d;
}

Deno.serve(async req => {
  if(req.method === "OPTIONS") return new Response("ok", {headers:C});
  if(req.method !== "POST") return out({error:"method_not_allowed"},405);

  try{
    const ah = req.headers.get("Authorization");
    if(!ah) return out({error:"authentication_required"},401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const srv = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const auth = createClient(url, anon, {
      global:{headers:{Authorization:ah}},
      auth:{autoRefreshToken:false,persistSession:false}
    });
    const admin = createClient(url, srv, {
      auth:{autoRefreshToken:false,persistSession:false}
    });

    const {data:u,error:ue} = await auth.auth.getUser();
    if(ue || !u?.user) return out({error:"invalid_session"},401);

    const {data:p,error:pe} = await admin
      .from("profiles")
      .select("id,box_id,role")
      .eq("id",u.user.id)
      .single();

    if(pe || !p?.box_id || !["box_admin","super_admin"].includes(p.role)){
      return out({error:"box_admin_required"},403);
    }

    const {data:b,error:be} = await admin
      .from("boxes")
      .select("id,name,contact_email,stripe_account_id,stripe_connect_status,stripe_connect_charges_enabled,stripe_connect_payouts_enabled,stripe_connect_details_submitted")
      .eq("id",p.box_id)
      .single();

    if(be || !b) return out({error:"box_not_found"},404);

    const body = await req.json().catch(()=>({}));
    const action = String(body?.action || "status");
    const origin = new URL(req.url).origin;

    let acct = b.stripe_account_id;

    // WodIO creates a Stripe account owned by the box. The connected
    // account gets the full Stripe Dashboard and Stripe remains liable
    // for negative balances on that connected account.
    if(action === "connect" && !acct){
      const q = new URLSearchParams();
      if(u.user.email) q.set("email",u.user.email);
      q.set("controller[fees][payer]","account");
      q.set("controller[losses][payments]","stripe");
      q.set("controller[requirement_collection]","stripe");
      q.set("controller[stripe_dashboard][type]","full");
      q.set("metadata[box_id]",b.id);
      q.set("metadata[wodio_managed]","true");

      const a = await stripe("/v1/accounts",q);
      acct = a.id;

      await admin.from("boxes").update({
        stripe_account_id:acct,
        stripe_connect_status:"pending",
        stripe_connect_charges_enabled:!!a.charges_enabled,
        stripe_connect_payouts_enabled:!!a.payouts_enabled,
        stripe_connect_details_submitted:!!a.details_submitted,
        stripe_connect_updated_at:new Date().toISOString()
      }).eq("id",b.id);
    }

    if(action === "status" && acct){
      const a = await stripe(
        "/v1/accounts/" + encodeURIComponent(acct),
        undefined,
        "GET"
      );

      const connected = !!a.charges_enabled && !!a.payouts_enabled;
      const status = connected
        ? "connected"
        : a.details_submitted
          ? "restricted"
          : "pending";

      await admin.from("boxes").update({
        stripe_connect_status:status,
        stripe_connect_charges_enabled:!!a.charges_enabled,
        stripe_connect_payouts_enabled:!!a.payouts_enabled,
        stripe_connect_details_submitted:!!a.details_submitted,
        stripe_connect_updated_at:new Date().toISOString()
      }).eq("id",b.id);

      return out({
        connected,
        status,
        account_id:a.id,
        charges_enabled:!!a.charges_enabled,
        payouts_enabled:!!a.payouts_enabled,
        details_submitted:!!a.details_submitted,
        currently_due:a.requirements?.currently_due || [],
        past_due:a.requirements?.past_due || [],
        dashboard_type:a.controller?.stripe_dashboard?.type || "full",
        losses_responsibility:a.controller?.losses?.payments || "stripe",
        fees_responsibility:a.controller?.fees?.payer || "account"
      });
    }

    if(action === "status"){
      return out({
        connected:false,
        status:"not_connected",
        charges_enabled:false,
        payouts_enabled:false,
        details_submitted:false,
        dashboard_type:"full",
        losses_responsibility:"stripe",
        fees_responsibility:"account"
      });
    }

    if(!acct) return out({error:"stripe_account_creation_failed"},400);

    const q = new URLSearchParams();
    q.set("account",acct);
    q.set("refresh_url",body?.refresh_url || origin + "/box-admin.html#stripe");
    q.set("return_url",body?.return_url || origin + "/box-admin.html#stripe");
    q.set("type","account_onboarding");

    const link = await stripe("/v1/account_links",q);

    return out({
      connected:false,
      status:"pending",
      account_id:acct,
      onboarding_url:link.url,
      expires_at:link.expires_at,
      dashboard_type:"full",
      losses_responsibility:"stripe",
      fees_responsibility:"account"
    });
  }catch(e){
    const m = e instanceof Error ? e.message : "unexpected_error";
    const code = (e as any)?.stripe_code || null;
    const lower = m.toLowerCase();

    let action_required = null;
    if(lower.includes("platform profile") || lower.includes("signed up for connect") || lower.includes("complete your platform")){
      action_required = "stripe_connect_platform_profile";
    }else if(lower.includes("branding") || lower.includes("icon")){
      action_required = "stripe_connect_branding";
    }else if(lower.includes("activated")){
      action_required = "stripe_account_activation";
    }

    const status = m === "STRIPE_SECRET_KEY_not_configured"
      ? 503
      : action_required
        ? 200
        : 400;

    return out({
      ok:false,
      error:m,
      error_code:code,
      action_required
    },status);
  }
});
