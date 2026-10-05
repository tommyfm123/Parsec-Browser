import AppKit
import WebKit

@MainActor
struct VideoFullscreenWindowSession {
    private var ownsWindowFullscreen = false
    private var cancelledEnter = false
    private var restoredLevel: NSWindow.Level?

    mutating func enter(_ window: NSWindow?) {
        guard let window, !ownsWindowFullscreen, !window.styleMask.contains(.fullScreen) else { return }
        if window.level != .normal {
            restoredLevel = window.level
            window.level = .normal
        }
        ownsWindowFullscreen = true
        cancelledEnter = false
        window.toggleFullScreen(nil)
    }

    mutating func exit(_ window: NSWindow?) {
        guard ownsWindowFullscreen else { return }
        ownsWindowFullscreen = false
        guard window?.styleMask.contains(.fullScreen) == true else {
            cancelledEnter = true
            return
        }
        window?.toggleFullScreen(nil)
    }

    mutating func windowDidEnter(_ window: NSWindow?) {
        guard cancelledEnter else { return }
        cancelledEnter = false
        window?.toggleFullScreen(nil)
    }

    mutating func windowDidExit(_ window: NSWindow?) {
        ownsWindowFullscreen = false
        cancelledEnter = false
        guard let restoredLevel, let window else { return }
        window.level = restoredLevel
        self.restoredLevel = nil
    }

    mutating func cancel() {
        ownsWindowFullscreen = false
        cancelledEnter = false
        restoredLevel = nil
    }
}

@MainActor
enum InWindowFullscreen {
    static let handlerName = "parsecFullscreen"
    static let enterAction = "enter"
    static let exitAction = "exit"
    static let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)

    private static let script = """
    (() => {
        if (window.__parsecInWindowFullscreen) return;
        window.__parsecInWindowFullscreen = true;
        const handlerName = '\(handlerName)';
        const enterAction = '\(enterAction)';
        const exitAction = '\(exitAction)';
        const frameMessage = 'parsecFullscreen';
        const forceExitAction = 'force-exit';
        const targetClass = 'parsec-fullscreen-target';
        const documentClass = 'parsec-in-window-fullscreen';
        const fullscreenStyle = {
            position: 'fixed', top: '0', right: '0', bottom: '0', left: '0', width: '100%', height: '100%',
            'max-width': 'none', 'max-height': 'none', margin: '0', 'z-index': '2147483647', background: '#000', transform: 'none'
        };
        const previousStyles = new WeakMap();
        let currentElement = null;
        const style = document.createElement('style');
        style.textContent = 'html.' + documentClass + ',html.' + documentClass + ' body{overflow:hidden !important;background:#000 !important}html.' + documentClass + ' .' + targetClass + ',html.' + documentClass + '.' + targetClass + '{position:fixed !important;top:0 !important;right:0 !important;bottom:0 !important;left:0 !important;width:100% !important;height:100% !important;max-width:none !important;max-height:none !important;margin:0 !important;z-index:2147483647 !important;background:#000 !important;transform:none !important}';
        (document.head || document.documentElement).appendChild(style);
        const define = (object, name, getter) => {
            try { Object.defineProperty(object, name, { configurable: true, get: getter }); } catch (error) {}
        };
        const notify = action => {
            try { window.webkit.messageHandlers[handlerName].postMessage(action); } catch (error) {}
        };
        const dispatch = () => {
            document.dispatchEvent(new Event('fullscreenchange', { bubbles: true }));
            document.dispatchEvent(new Event('webkitfullscreenchange', { bubbles: true }));
        };
        const cover = target => {
            const previous = {};
            Object.keys(fullscreenStyle).forEach(name => { previous[name] = target.style.getPropertyValue(name); });
            previousStyles.set(target, previous);
            target.classList.add(targetClass);
            Object.entries(fullscreenStyle).forEach(([name, value]) => target.style.setProperty(name, value, 'important'));
        };
        const uncover = target => {
            target.classList.remove(targetClass);
            const previous = previousStyles.get(target);
            previousStyles.delete(target);
            Object.keys(fullscreenStyle).forEach(name => {
                const value = previous && previous[name];
                if (value) target.style.setProperty(name, value);
                else target.style.removeProperty(name);
            });
        };
        const updateDocument = () => document.documentElement.classList.toggle(documentClass, currentElement !== null);
        const release = () => {
            const previous = currentElement;
            if (!previous) return null;
            uncover(previous);
            currentElement = null;
            updateDocument();
            dispatch();
            return previous;
        };
        const enter = target => {
            if (!(target instanceof Element) || currentElement === target) return;
            const previous = currentElement;
            if (previous) uncover(previous);
            currentElement = target;
            cover(target);
            updateDocument();
            dispatch();
            if (previous instanceof HTMLIFrameElement) previous.contentWindow?.postMessage({ [frameMessage]: forceExitAction }, '*');
            if (window === window.top) notify(enterAction);
            else window.parent.postMessage({ [frameMessage]: enterAction }, '*');
        };
        const exit = () => {
            if (!currentElement) return Promise.resolve();
            const previous = release();
            if (previous instanceof HTMLIFrameElement) previous.contentWindow?.postMessage({ [frameMessage]: forceExitAction }, '*');
            if (window === window.top) notify(exitAction);
            else window.parent.postMessage({ [frameMessage]: exitAction }, '*');
            return Promise.resolve();
        };
        const forceExit = () => {
            const previous = release();
            if (previous instanceof HTMLIFrameElement) previous.contentWindow?.postMessage({ [frameMessage]: forceExitAction }, '*');
        };
        const hasGesture = () => navigator.userActivation?.isActive === true;
        function requestFullscreen() {
            if (!(this instanceof Element)) return Promise.reject(new TypeError('Failed to execute requestFullscreen'));
            if (!hasGesture()) {
                document.dispatchEvent(new Event('fullscreenerror', { bubbles: true }));
                return Promise.reject(new DOMException('Permissions check failed', 'NotAllowedError'));
            }
            enter(this);
            return Promise.resolve();
        }
        ['requestFullscreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen'].forEach(name => {
            try { Element.prototype[name] = requestFullscreen; } catch (error) {}
        });
        ['exitFullscreen', 'webkitExitFullscreen', 'webkitCancelFullScreen'].forEach(name => {
            try { Document.prototype[name] = () => exit(); } catch (error) {}
        });
        const elementGetter = () => currentElement;
        ['fullscreenElement', 'webkitFullscreenElement', 'webkitCurrentFullScreenElement'].forEach(name => define(Document.prototype, name, elementGetter));
        define(Document.prototype, 'webkitIsFullScreen', () => currentElement !== null);
        define(document, 'fullscreenElement', elementGetter);
        define(document, 'webkitFullscreenElement', elementGetter);
        if (window.HTMLVideoElement) {
            try {
                HTMLVideoElement.prototype.webkitEnterFullscreen = function () { requestFullscreen.call(this); };
                HTMLVideoElement.prototype.webkitEnterFullScreen = HTMLVideoElement.prototype.webkitEnterFullscreen;
                HTMLVideoElement.prototype.webkitExitFullscreen = function () { exit(); };
                HTMLVideoElement.prototype.webkitExitFullScreen = HTMLVideoElement.prototype.webkitExitFullscreen;
            } catch (error) {}
            define(HTMLVideoElement.prototype, 'webkitSupportsFullscreen', () => true);
            define(HTMLVideoElement.prototype, 'webkitDisplayingFullscreen', function () { return currentElement === this; });
        }
        window.addEventListener('message', event => {
            const action = event.data && event.data[frameMessage];
            if (action === forceExitAction) {
                if (event.source !== window.parent) return;
                forceExit();
                return;
            }
            if (action !== enterAction && action !== exitAction) return;
            const frame = Array.from(document.querySelectorAll('iframe')).find(candidate => candidate.contentWindow === event.source);
            if (!frame) return;
            if (action === enterAction) enter(frame);
            else if (currentElement === frame) exit();
        });
        document.addEventListener('keydown', event => {
            if (event.key !== 'Escape' || !currentElement) return;
            event.preventDefault();
            exit();
        }, true);
    })();
    """
}

@MainActor
final class InWindowFullscreenRouter: NSObject, WKScriptMessageHandler {
    static let shared = InWindowFullscreenRouter()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == InWindowFullscreen.handlerName, message.frameInfo.isMainFrame,
              let webView = message.webView, let page = WebPage.page(for: webView),
              let action = message.body as? String else { return }
        switch action {
        case InWindowFullscreen.enterAction: page.host?.setVideoFullscreen(true, page: page)
        case InWindowFullscreen.exitAction: page.host?.setVideoFullscreen(false, page: page)
        default: break
        }
    }
}
