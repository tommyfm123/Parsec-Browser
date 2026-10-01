import WebKit

@MainActor
enum AutoPictureInPicture {
    private static let world = WKContentWorld.world(name: "parsec-pictureinpicture")
    private static let intentTrackingSource = """
    (() => {
        const chosenVideos = new WeakSet();
        const isInside = (event, video) => {
            const bounds = video.getBoundingClientRect();
            return event.clientX >= bounds.left && event.clientX <= bounds.right && event.clientY >= bounds.top && event.clientY <= bounds.bottom;
        };
        document.addEventListener('pointerdown', event => {
            document.querySelectorAll('video').forEach(video => { if (isInside(event, video)) chosenVideos.add(video); });
        }, true);
        document.addEventListener('play', event => {
            if (event.target instanceof HTMLVideoElement && navigator.userActivation?.isActive) chosenVideos.add(event.target);
        }, true);
        window.parsecIsChosenVideo = video => chosenVideos.has(video) || (!video.muted && video.volume > 0 && navigator.userActivation?.hasBeenActive === true);
    })();
    """
    private static let enterScript = """
    if (document.pictureInPictureElement || !document.pictureInPictureEnabled || !window.parsecIsChosenVideo) return false;
    const playingVideos = Array.from(document.querySelectorAll('video')).filter(video => !video.paused && !video.ended && video.readyState >= 2 && video.videoWidth > 0 && !video.disablePictureInPicture && window.parsecIsChosenVideo(video));
    if (playingVideos.length === 0) return false;
    playingVideos.sort((first, second) => second.videoWidth * second.videoHeight - first.videoWidth * first.videoHeight);
    try {
        await playingVideos[0].requestPictureInPicture();
        return true;
    } catch (error) {
        return false;
    }
    """
    private static let exitScript = """
    if (!document.pictureInPictureElement) return false;
    try {
        await document.exitPictureInPicture();
        return true;
    } catch (error) {
        return false;
    }
    """

    static let intentTrackingScript = WKUserScript(source: intentTrackingSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)

    static func enter(_ page: WebPage?) {
        run(enterScript, on: page)
    }

    static func exit(_ page: WebPage?) {
        run(exitScript, on: page)
    }

    private static func run(_ script: String, on page: WebPage?) {
        guard let webView = page?.webView else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world)
        }
    }
}
