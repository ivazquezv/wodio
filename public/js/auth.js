document.addEventListener("DOMContentLoaded", () => {
  const loginForm = document.getElementById("loginForm");
  const loginBtn = document.getElementById("loginBtn");
  const loginBtnText = document.getElementById("loginBtnText");
  const loginMessage = document.getElementById("loginMessage");

  if (!loginForm) {
    return;
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

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    hideMessage();

    const email = document.getElementById("email").value.trim();

    const password = document.getElementById("password").value;

    if (!email || !password) {
      showMessage("Introduce tu correo electrónico y contraseña.");

      return;
    }

    loginBtn.disabled = true;

    loginBtnText.textContent = "Iniciando sesión...";

    const loginIcon = loginBtn.querySelector("i");

    if (loginIcon) {
      loginIcon.className = "ph ph-spinner-gap";
    }

    try {
      const { data, error } = await supabaseClient.auth.signInWithPassword({
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
          showMessage("Tu correo electrónico todavía no está confirmado.");
        } else {
          showMessage(
            message || "No se ha podido iniciar sesión. Inténtalo de nuevo."
          );
        }

        return;
      }

      console.log("Usuario autenticado:", data.user);

      console.log("Sesión:", data.session);

      showMessage("Acceso correcto. Entrando en WodIO...", "success");

      setTimeout(() => {
        window.location.href = "dashboard.html";
      }, 500);
    } catch (error) {
      console.error("[WodIO] Error inesperado:", error);

      showMessage(
        error?.message || "Se ha producido un error inesperado."
      );
    } finally {
      loginBtn.disabled = false;

      loginBtnText.textContent = "Iniciar sesión";

      if (loginIcon) {
        loginIcon.className = "ph ph-sign-in";
      }
    }
  });
});
