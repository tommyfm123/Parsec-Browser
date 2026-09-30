import WebKit

@MainActor
enum AutoPictureInPicture {
    private static let enterScript = """
    if (document.pictureInPictureElement || !document.pictureInPictureEnabled) return false;
    const playingVideos = Array.from(document.querySelectorAll('video')).filter(video => !video.paused && !video.ended && video.readyState >= 2 && video.videoWidth > 0 && !video.disablePictureInPicture);
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

    static func enter(_ page: WebPage?) {
        run(enterScript, on: page)
    }

    static func exit(_ page: WebPage?) {
        run(exitScript, on: page)
    }

    private static func run(_ script: String, on page: WebPage?) {
        guard let webView = page?.webView else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        }
    }
}
