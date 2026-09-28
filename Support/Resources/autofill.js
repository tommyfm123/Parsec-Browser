(() => {
  const HANDLER_NAME = "parsecAutofill";
  const USERNAME_SELECTOR = "input[type=email], input[type=text], input[autocomplete=username], input:not([type])";
  const PASSWORD_SELECTOR = "input[type=password]";
  const SUBMIT_SELECTOR = "button[type=submit], input[type=submit], button:not([type])";
  let hasReportedForm = false;

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

  const reportFormIfPresent = () => {
    if (hasReportedForm || visiblePasswordFields().length === 0) return;
    hasReportedForm = true;
    post({ type: "formDetected" });
  };

  const reportSubmission = () => {
    const passwordField = visiblePasswordFields().find((field) => field.value);
    if (!passwordField) return;
    const usernameField = usernameFieldFor(passwordField);
    post({ type: "submitted", username: usernameField ? usernameField.value : "", password: passwordField.value });
  };

  window.parsecFillCredentials = (username, password) => {
    const passwordField = visiblePasswordFields()[0];
    if (!passwordField) return false;
    const usernameField = usernameFieldFor(passwordField);
    if (usernameField && username) setFieldValue(usernameField, username);
    setFieldValue(passwordField, password);
    return true;
  };

  document.addEventListener("submit", reportSubmission, true);
  document.addEventListener(
    "click",
    (event) => {
      if (event.target instanceof Element && event.target.closest(SUBMIT_SELECTOR)) reportSubmission();
    },
    true
  );
  new MutationObserver(reportFormIfPresent).observe(document.documentElement, { childList: true, subtree: true });
  reportFormIfPresent();
})();
