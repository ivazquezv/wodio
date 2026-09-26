document.addEventListener("DOMContentLoaded", async () => {
  const title = document.getElementById("confirmation-title");
  const description = document.getElementById(
    "confirmationDescription",
  );
  const icon = document.getElementById("confirmationIcon");
  const message = document.getElementById("confirmationMessage");
  const actions = document.getElementById("confirmationActions");

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

  function getAuthParams() {
    if (!window.location.hash) {
      return new URLSearchParams();
    }

    return new URLSearchParams(window.location.hash.slice(1));
  }

  function setState({
    titleText,
    descriptionText,
    messageText,
    messageType = "error",
    iconClass,
  }) {
    title.textContent = titleText;
    description.textContent = descriptionText;

    icon.innerHTML =
      '<i class="ph ' + iconClass + '" aria-hidden="true"></i>';

    message.textContent = messageText;
    message.hidden = false;

    message.classList.remove("success", "error");
    message.classList.add(messageType);

    actions.hidden = false;
  }

  try {
    const params = getAuthParams();

    const errorCode = params.get("error_code");
    const errorDescription = params.get("error_description");
    const authError = params.get("error");

    if (errorCode || authError) {
      if (errorCode === "otp_expired") {
        setState({
          titleText: "Enlace caducado",
          descriptionText:
            "El enlace de confirmación ya no es válido.",
          messageText:
            "Este enlace ha caducado o ya ha sido utilizado. Ve a iniciar sesión y solicita un nuevo correo de confirmación.",
          iconClass: "ph-warning-circle",
        });
      } else {
        let decodedDescription =
          "No se ha podido confirmar tu correo electrónico.";

        if (errorDescription) {
          try {
            decodedDescription = decodeURIComponent(
              errorDescription.replace(/\+/g, " "),
            );
          } catch (decodeError) {
            console.warn(
              "[WodIO] No se pudo decodificar el error de confirmación:",
              decodeError,
            );
          }
        }

        setState({
          titleText: "No se ha podido confirmar",
          descriptionText:
            "El correo electrónico no se ha podido verificar.",
          messageText: decodedDescription,
          iconClass: "ph-x-circle",
        });
      }

      clearAuthHash();

      return;
    }

    const { data, error } =
      await supabaseClient.auth.getSession();

    if (error) {
      console.error(
        "[WodIO] Error obteniendo la sesión de confirmación:",
        error,
      );

      setState({
        titleText: "No se ha podido confirmar",
        descriptionText:
          "Se ha producido un error al verificar tu correo.",
        messageText:
          error.message ||
          "Vuelve a solicitar el correo de confirmación e inténtalo de nuevo.",
        iconClass: "ph-x-circle",
      });

      clearAuthHash();

      return;
    }

    if (data.session?.user) {
      setState({
        titleText: "Correo confirmado",
        descriptionText:
          "Tu cuenta de WodIO ya está activa.",
        messageText:
          "Tu correo electrónico se ha confirmado correctamente. Ya puedes iniciar sesión con tus credenciales.",
        messageType: "success",
        iconClass: "ph-check-circle",
      });

      try {
        window.localStorage.removeItem(
          "wodio.pendingConfirmationEmail",
        );
      } catch (storageError) {
        console.warn(
          "[WodIO] No se pudo limpiar el correo pendiente:",
          storageError,
        );
      }

      clearAuthHash();

      return;
    }

    setState({
      titleText: "Confirmación no disponible",
      descriptionText:
        "No hemos encontrado una confirmación válida.",
      messageText:
        "Abre el enlace desde el correo de confirmación más reciente. Si ha caducado, solicita uno nuevo desde el inicio de sesión.",
      iconClass: "ph-envelope-simple-open",
    });

    clearAuthHash();
  } catch (error) {
    console.error(
      "[WodIO] Error inesperado en la confirmación:",
      error,
    );

    setState({
      titleText: "Se ha producido un error",
      descriptionText:
        "No hemos podido completar la confirmación.",
      messageText:
        error?.message ||
        "Vuelve a solicitar el correo de confirmación e inténtalo de nuevo.",
      iconClass: "ph-x-circle",
    });

    clearAuthHash();
  }
});
