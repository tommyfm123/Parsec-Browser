(() => {
  const HANDLER_NAME = "parsecAutofill";
  const USERNAME_SELECTOR = "input[type=email], input[type=text], input[autocomplete=username], input:not([type])";
  const PASSWORD_SELECTOR = "input[type=password]";
  const SUBMIT_SELECTOR = "button[type=submit], input[type=submit], button:not([type])";
  const USERNAME_HINT = /user|e-?mail|login|identifier|account/i;
  let hasReportedForm = false;
  let hasReportedUsernameField = false;
  const documentID = crypto.randomUUID();
  window.parsecCredentialDocumentID = documentID;
  const hasSafeDestination = (field) => {
    const destination = new URL(field.form?.action || location.href, location.href);
    return location.protocol === "https:" && destination.origin === location.origin;
  };

  const post = (payload) => window.webkit.messageHandlers[HANDLER_NAME].postMessage(payload);

  const visiblePasswordFields = () =>
    Array.from(document.querySelectorAll(PASSWORD_SELECTOR)).filter((field) => field.offsetParent !== null);

  const usernameFieldFor = (passwordField) => {
    const scope = passwordField.form || document;
    const candidates = Array.from(scope.querySelectorAll(USERNAME_SELECTOR)).filter((field) => field.offsetParent !== null);
    const preceding = candidates.filter(
      (field) => field.compareDocumentPosition(passwordField) & Node.DOCUMENT_POSITION_FOLLOWING
    );
    return preceding[preceding.length - 1] || candidates[0] || null;
  };

  const setFieldValue = (field, value) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(field, value);
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  };

  const isLoginUsernameField = (field) =>
    field instanceof HTMLInputElement &&
    field.matches(USERNAME_SELECTOR) &&
    field.offsetParent !== null &&
    (field.type === "email" || USERNAME_HINT.test(`${field.autocomplete} ${field.name} ${field.id}`));

  const reportFormIfPresent = () => {
    const hasPasswordField = visiblePasswordFields().length > 0;
    if (!hasPasswordField) hasReportedForm = false;
    if (hasPasswordField && !hasReportedForm) {
      hasReportedForm = true;
      post({ type: "formDetected" });
    }
    reportUsernameFocus();
  };

  const reportUsernameFocus = () => {
    if (hasReportedUsernameField || visiblePasswordFields().length > 0 || !isLoginUsernameField(document.activeElement)) return;
    hasReportedUsernameField = true;
    post({ type: "usernameFocused" });
  };

  const reportSubmission = () => {
    const passwordField = visiblePasswordFields().find((field) => field.value);
    if (!passwordField || !hasSafeDestination(passwordField)) return;
    const usernameField = usernameFieldFor(passwordField);
    post({ type: "submitted", username: usernameField ? usernameField.value : "", password: passwordField.value });
  };

  window.parsecFillCredentials = (username, password, expectedDocumentID, expectedOrigin) => {
    if (documentID !== expectedDocumentID || location.origin !== expectedOrigin) return false;
    const passwordField = visiblePasswordFields()[0];
    if (!passwordField) return fillUsernameOnly(username);
    if (!hasSafeDestination(passwordField)) return "none";
    const usernameField = usernameFieldFor(passwordField);
    if (usernameField && username) setFieldValue(usernameField, username);
    setFieldValue(passwordField, password);
    return "full";
  };

  const fillUsernameOnly = (username) => {
    const field = isLoginUsernameField(document.activeElement)
      ? document.activeElement
      : Array.from(document.querySelectorAll(USERNAME_SELECTOR)).find(isLoginUsernameField);
    if (!field || !username || !hasSafeDestination(field)) return "none";
    setFieldValue(field, username);
    return "username";
  };

  document.addEventListener("submit", reportSubmission, true);
  document.addEventListener(
    "click",
    (event) => {
      if (event.target instanceof Element && event.target.closest(SUBMIT_SELECTOR)) reportSubmission();
    },
    true
  );
  document.addEventListener("focusin", () => {
    hasReportedUsernameField = false;
    reportUsernameFocus();
  }, true);
  const formObserver = new MutationObserver(reportFormIfPresent);
  formObserver.observe(document.documentElement, { childList: true, subtree: true });
  reportFormIfPresent();
})();
