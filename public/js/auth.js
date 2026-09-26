document.addEventListener("DOMContentLoaded", async () => {
  const loginForm = document.getElementById("loginForm");
  const loginBtn = document.getElementById("loginBtn");
  const loginBtnText = document.getElementById("loginBtnText");
  const loginMessage = document.getElementById("loginMessage");
  const emailInput = document.getElementById("email");
  const resendConfirmationBtn = document.getElementById(
    "resendConfirmationBtn",
  );
  const resendConfirmationText = document.getElementById(
    "resendConfirmationText",
  );

  if (!loginForm) {
    return;
  }

  const PENDING_EMAIL_KEY = "wodio.pendingConfirmationEmail";

  function getAuthRedirectUrl() {
    return new URL("confirm-email.html", window.location.href).href;
  }

  function showMessage(message, type = "error") {
    loginMessage.textContent = message;
    loginMessage.hidden = false;

    loginMessage.classList.remove("success", "error");
    loginMessage.classList.add(type);
  }

  function hideMessage() {
    loginMessage.hidden = true;
    loginMessage.textContent = "";

    loginMessage.classList.remove("success", "error");
  }

  function showResendButton() {
    if (resendConfirmationBtn) {
      resendConfirmationBtn.hidden = false;
    }
  }

  function hideResendButton() {
    if (resendConfirmationBtn) {
      resendConfirmationBtn.hidden = true;
    }
  }

  function getPendingEmail() {
    try {
      return (
        window.localStorage.getItem(PENDING_EMAIL_KEY) ||
        emailInput.value.trim()
      );
    } catch (error) {
      console.warn(
        "[WodIO] No se pudo leer el correo pendiente:",
        error,
      );

      return emailInput.value.trim();
    }
  }

  function savePendingEmail(email) {
    try {
      window.localStorage.setItem(PENDING_EMAIL_KEY, email);
    } catch (error) {
      console.warn(
        "[WodIO] No se pudo guardar el correo pendiente:",
        error,
      );
    }
  }

  function clearPendingEmail() {
    try {
      window.localStorage.removeItem(PENDING_EMAIL_KEY);
    } catch (error) {
      console.warn(
        "[WodIO] No se pudo eliminar el correo pendiente:",
        error,
      );
    }
  }

  function clearAuthHash() {
    if (!window.location.hash) {
      return;
    }

    window.history.replaceState(
      null,
      document.title,
      window.location.pathname + window.location.search,
    );
  }

  function parseAuthHash() {
    if (!window.location.hash) {
      return new URLSearchParams();
    }

    return new URLSearchParams(window.location.hash.slice(1));
  }

  async function handleAuthRedirect() {
    const params = parseAuthHash();

    if (!params.toString()) {
      return;
    }

    const errorCode = params.get("error_code");
    const errorDescription = params.get("error_description");
    const authError = params.get("error");

    if (errorCode || authError) {
      clearAuthHash();

      if (errorCode === "otp_expired") {
        showMessage(
          "El enlace de confirmación ha caducado o ya ha sido utilizado. Puedes solicitar un nuevo correo de confirmación.",
        );
      } else {
        showMessage(
          errorDescription
            ? decodeURIComponent(errorDescription.replace(/\+/g, " "))
            : "No se ha podido confirmar el correo electrónico. Solicita un nuevo correo de confirmación.",
        );
      }

      const pendingEmail = getPendingEmail();

      if (pendingEmail) {
        emailInput.value = pendingEmail;
      }

      showResendButton();

      return;
    }

    const authType = params.get("type");
    const accessToken = params.get("access_token");

    if (authType === "signup" && accessToken) {
      showMessage(
        "Correo electrónico confirmado correctamente. Ya puedes iniciar sesión.",
        "success",
      );

      clearPendingEmail();
      clearAuthHash();

      return;
    }

    clearAuthHash();
  }

  async function resendConfirmation() {
    const email = emailInput.value.trim();

    if (!email) {
      showMessage(
        "Introduce tu correo electrónico para reenviar el mensaje de confirmación.",
      );

      emailInput.focus();

      return;
    }

    if (!emailInput.validity.valid) {
      showMessage(
        "Introduce un correo electrónico válido para reenviar la confirmación.",
      );

      emailInput.focus();

      return;
    }

    resendConfirmationBtn.disabled = true;
    resendConfirmationText.textContent = "Enviando...";

    try {
      const { error } = await supabaseClient.auth.resend({
        type: "signup",
        email,
        options: {
          emailRedirectTo: getAuthRedirectUrl(),
        },
      });

      if (error) {
        console.error(
          "[WodIO] Error al reenviar confirmación:",
          error,
        );

        const message = error.message || "";
        const normalizedMessage = message.toLowerCase();

        if (normalizedMessage.includes("rate limit")) {
          showMessage(
            "Se han realizado demasiados intentos. Espera unos minutos antes de solicitar otro correo.",
          );
        } else {
          showMessage(
            message ||
              "No se ha podido reenviar el correo de confirmación. Inténtalo de nuevo.",
          );
        }

        return;
      }

      savePendingEmail(email);

      showMessage(
        "Te hemos enviado un nuevo correo de confirmación. Usa el enlace del mensaje más reciente.",
        "success",
      );

      hideResendButton();
    } catch (error) {
      console.error(
        "[WodIO] Error inesperado al reenviar confirmación:",
        error,
      );

      showMessage(
        error?.message ||
          "Se ha producido un error al reenviar el correo de confirmación.",
      );
    } finally {
      resendConfirmationBtn.disabled = false;
      resendConfirmationText.textContent =
        "Reenviar correo de confirmación";
    }
  }

  try {
    await handleAuthRedirect();
  } catch (error) {
    console.error(
      "[WodIO] Error procesando la confirmación:",
      error,
    );
  }

  try {
    const pendingEmail = getPendingEmail();

    if (pendingEmail && !emailInput.value.trim()) {
      emailInput.value = pendingEmail;
    }
  } catch (error) {
    console.warn(
      "[WodIO] No se pudo recuperar el correo pendiente:",
      error,
    );
  }

  if (resendConfirmationBtn) {
    resendConfirmationBtn.addEventListener(
      "click",
      resendConfirmation,
    );
  }

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    hideMessage();
    hideResendButton();

    const email = emailInput.value.trim();
    const password = document.getElementById("password").value;

    if (!email || !password) {
      showMessage("Introduce tu correo electrónico y contraseña.");

      return;
    }

    loginBtn.disabled = true;
    loginBtn.setAttribute("aria-busy", "true");

    loginBtnText.textContent = "Iniciando sesión...";

    const loginIcon = loginBtn.querySelector("i");

    if (loginIcon) {
      loginIcon.className = "ph ph-spinner-gap";
    }

    try {
      const { data, error } =
        await supabaseClient.auth.signInWithPassword({
          email,
          password,
        });

      if (error) {
        console.error("[WodIO] Error de Supabase:", error);

        const message = error.message || "";
        const normalizedMessage = message.toLowerCase();

        if (normalizedMessage === "invalid login credentials") {
          showMessage(
            "El correo electrónico o la contraseña no son correctos.",
          );
        } else if (
          normalizedMessage.includes("email not confirmed")
        ) {
          savePendingEmail(email);

          showMessage(
            "Tu correo electrónico todavía no está confirmado. Revisa tu bandeja de entrada o solicita un nuevo correo de confirmación.",
          );

          showResendButton();
        } else {
          showMessage(
            message ||
              "No se ha podido iniciar sesión. Inténtalo de nuevo.",
          );
        }

        return;
      }

      clearPendingEmail();

      console.log("Usuario autenticado:", data.user);
      console.log("Sesión:", data.session);

      showMessage(
        "Acceso correcto. Entrando en WodIO...",
        "success",
      );

      const { data: profile } = await supabaseClient
        .from("profiles")
        .select("role")
        .eq("id", data.user.id)
        .maybeSingle();

      const destination = ({
        athlete: "dashboard.html",
        coach: "coach-dashboard.html",
        box_admin: "box-admin.html",
        super_admin: "super-admin.html"
      })[profile?.role] || "dashboard.html";

      setTimeout(() => {
        window.location.href = destination;
      }, 250);
    } catch (error) {
      console.error("[WodIO] Error inesperado:", error);

      showMessage(
        error?.message ||
          "Se ha producido un error inesperado.",
      );
    } finally {
      loginBtn.disabled = false;
      loginBtn.removeAttribute("aria-busy");

      loginBtnText.textContent = "Iniciar sesión";

      if (loginIcon) {
        loginIcon.className = "ph ph-sign-in";
      }
    }
  });
});
