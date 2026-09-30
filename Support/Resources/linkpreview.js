(() => {
  const HANDLER_NAME = "parsecLinkPreview";
  const WEB_PROTOCOLS = ["http:", "https:"];
  let activeAnchor = null;

  const post = (payload) => window.webkit.messageHandlers[HANDLER_NAME].postMessage(payload);

  const anchorFor = (target) => (target && target.closest ? target.closest("a[href]") : null);

  const isPreviewable = (anchor) => {
    if (!WEB_PROTOCOLS.includes(anchor.protocol)) return false;
    const isSamePageAnchor = anchor.origin === location.origin && anchor.pathname === location.pathname && anchor.search === location.search;
    return !isSamePageAnchor;
  };

  const rectNearPointer = (anchor, event) => {
    const rects = Array.from(anchor.getClientRects());
    const containing = rects.find(
      (rect) => event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom
    );
    return containing || anchor.getBoundingClientRect();
  };

  const beginPreview = (anchor, event) => {
    const rect = rectNearPointer(anchor, event);
    activeAnchor = anchor;
    post({ type: "enter", href: anchor.href, x: rect.left, y: rect.top, width: rect.width, height: rect.height });
  };

  const endPreview = (type) => {
    if (!activeAnchor) return;
    activeAnchor = null;
    post({ type });
  };

  document.addEventListener("mouseover", (event) => {
    const anchor = anchorFor(event.target);
    if (anchor === activeAnchor) return;
    endPreview("leave");
    if (anchor && isPreviewable(anchor)) beginPreview(anchor, event);
  }, true);

  document.addEventListener("mouseout", (event) => {
    if (!activeAnchor || activeAnchor.contains(event.relatedTarget)) return;
    endPreview("leave");
  }, true);

  document.addEventListener("mousedown", () => endPreview("dismiss"), true);
  document.addEventListener("scroll", () => endPreview("dismiss"), true);
})();
