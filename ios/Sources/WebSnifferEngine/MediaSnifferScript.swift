// [Intent] JavaScript sniffer injected into WKWebView to detect HTML5 video/audio and HLS streams
import Foundation
import WebKit

public struct MediaSnifferScript {
    public static let handlerName = "mediaSniffer"

    public static let sourceJavaScript: String = """
    (function() {
        if (window.__obsidianMediaSnifferInjected) return;
        window.__obsidianMediaSnifferInjected = true;

        function notifyStream(url, title) {
            if (!url || typeof url !== 'string') return;
            if (url.startsWith('blob:') || url.startsWith('data:')) return;

            var lower = url.toLowerCase();
            var isMedia = lower.includes('.m3u8') || lower.includes('.mp4') || lower.includes('.mp3') || lower.includes('.webm') || lower.includes('.m4a');
            if (isMedia) {
                var docTitle = title || document.title || 'Web Media Stream';
                window.webkit.messageHandlers.mediaSniffer.postMessage({
                    streamURL: url,
                    pageURL: window.location.href,
                    title: docTitle,
                    isHLS: lower.includes('.m3u8')
                });
            }
        }

        // 1. Scan existing DOM video/audio tags
        function scanDOM() {
            var mediaElements = document.querySelectorAll('video, audio, source');
            for (var i = 0; i < mediaElements.length; i++) {
                var el = mediaElements[i];
                var src = el.src || el.currentSrc;
                if (src) notifyStream(src, el.getAttribute('title') || document.title);
            }
        }

        // 2. MutationObserver for dynamic players
        var observer = new MutationObserver(function(mutations) {
            scanDOM();
        });
        observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });

        // 3. Intercept window.fetch
        var originalFetch = window.fetch;
        window.fetch = function() {
            var url = arguments[0];
            if (typeof url === 'string') notifyStream(url);
            else if (url && url.url) notifyStream(url.url);
            return originalFetch.apply(this, arguments);
        };

        scanDOM();
    })();
    """

    public static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: sourceJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
}
