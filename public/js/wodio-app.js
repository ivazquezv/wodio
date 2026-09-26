window.WodIOApp = (() => {
  async function requireUser({ roles = [] } = {}) {
    if (typeof supabaseClient === "undefined") {
      window.location.href = "login.html";
      return null;
    }

    const { data, error } = await supabaseClient.auth.getUser();

    if (error || !data?.user) {
      window.location.href = "login.html";
      return null;
    }

    const user = data.user;
    const { data: profile } = await supabaseClient
      .from("profiles")
      .select("id, first_name, last_name, role, box_id")
      .eq("id", user.id)
      .maybeSingle();

    if (roles.length && !roles.includes(profile?.role)) {
      window.location.href = roleHome(profile?.role);
      return null;
    }

    return { user, profile };
  }

  function roleHome(role) {
    return ({
      athlete: "dashboard.html",
      coach: "coach-dashboard.html",
      box_admin: "box-admin.html",
      super_admin: "super-admin.html"
    })[role] || "login.html";
  }

  function nameOf(profile, user) {
    return [profile?.first_name, profile?.last_name].filter(Boolean).join(" ").trim()
      || user?.email?.split("@")[0]
      || "Usuario";
  }

  function initials(profile, user) {
    const name = nameOf(profile, user).split(/\s+/).filter(Boolean);
    return ((name[0]?.[0] || "") + (name[1]?.[0] || "")).toUpperCase() || "U";
  }

  function formatDate(value, options = {}) {
    if (!value) return "—";
    return new Intl.DateTimeFormat("es-ES", {
      day: "2-digit",
      month: "short",
      ...(options.withYear ? { year: "numeric" } : {})
    }).format(new Date(value));
  }

  function formatDateTime(value) {
    if (!value) return "—";
    return new Intl.DateTimeFormat("es-ES", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date(value));
  }

  function formatTime(value) {
    if (!value) return "—";
    return new Intl.DateTimeFormat("es-ES", {
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date(value));
  }

  function euro(cents = 0) {
    return new Intl.NumberFormat("es-ES", {
      style: "currency",
      currency: "EUR"
    }).format(Number(cents || 0) / 100);
  }

  function escapeHtml(value = "") {
    return String(value).replace(/[&<>"']/g, char => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
    }[char]));
  }

  function message(element, text, type = "error") {
    if (!element) return;
    element.textContent = text;
    element.className = "app-message show" + (type === "success" ? " success" : "");
  }

  function clearMessage(element) {
    if (!element) return;
    element.textContent = "";
    element.className = "app-message";
  }

  async function logout() {
    await supabaseClient.auth.signOut();
    window.location.href = "login.html";
  }

  function bindLogout(id = "logoutButton") {
    document.getElementById(id)?.addEventListener("click", logout);
  }

  function profileLabel(profile) {
    return ({
      athlete: "Atleta",
      coach: "Coach",
      box_admin: "Administrador",
      super_admin: "Super administrador"
    })[profile?.role] || "Usuario";
  }

  return {
    requireUser,
    nameOf,
    initials,
    formatDate,
    formatDateTime,
    formatTime,
    euro,
    escapeHtml,
    message,
    clearMessage,
    logout,
    bindLogout,
    profileLabel,
    roleHome
  };
})();