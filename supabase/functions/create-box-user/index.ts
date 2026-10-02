import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Sesión no válida.");

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: actor }, error: actorError } = await authClient.auth.getUser();
    if (actorError || !actor) throw new Error("Sesión no válida.");

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const body = await req.json();
    const firstName = String(body.first_name || "").trim();
    const lastName = String(body.last_name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const phone = String(body.phone || "").trim() || null;
    const password = String(body.password || "");
    const boxId = String(body.box_id || "");

    if (!firstName || !email || !password || !boxId) throw new Error("Nombre, email, contraseña y box son obligatorios.");
    if (password.length < 8) throw new Error("La contraseña debe tener al menos 8 caracteres.");

    const { data: actorProfile, error: profileError } = await admin
      .from("profiles")
      .select("id,role,box_id")
      .eq("id", actor.id)
      .single();
    if (profileError || !actorProfile || actorProfile.role !== "box_admin" || actorProfile.box_id !== boxId) {
      return new Response(JSON.stringify({ error: "No tienes permisos para crear usuarios en este box." }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName, phone },
    });
    if (createError) throw createError;

    const userId = created.user?.id;
    if (!userId) throw new Error("No se pudo crear el usuario.");

    const { error: updateError } = await admin.from("profiles").update({
      first_name: firstName,
      last_name: lastName || null,
      phone,
      role: "athlete",
      box_id: boxId,
    }).eq("id", userId);
    if (updateError) {
      await admin.auth.admin.deleteUser(userId);
      throw updateError;
    }

    const { error: membershipError } = await admin.from("user_box_memberships").upsert(
      { user_id: userId, box_id: boxId },
      { onConflict: "user_id,box_id" }
    );
    if (membershipError) {
      await admin.auth.admin.deleteUser(userId);
      throw membershipError;
    }

    return new Response(JSON.stringify({
      user: { id: userId, email, first_name: firstName, last_name: lastName, phone, role: "athlete", box_id: boxId },
    }), { status: 201, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    const message = error?.message || "No se pudo crear el usuario.";
    return new Response(JSON.stringify({ error: message }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});