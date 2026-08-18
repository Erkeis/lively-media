// [Intent] Obsidian Studio In-App Web Browser tab with injected stream sniffer and unobtrusive floating pill alert
import SwiftUI
import WebKit
import WebSnifferEngine
import DownloadManagerEngine
import CastEngine

#if os(iOS)
public struct WebViewRepresentable: UIViewRepresentable {
    public let url: URL
    public let coordinator: WebBrowserCoordinator

    public init(url: URL, coordinator: WebBrowserCoordinator) {
        self.url = url
        self.coordinator = coordinator
    }

    public func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: MediaSnifferScript.handlerName)
        contentController.addUserScript(MediaSnifferScript.makeUserScript())

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

public struct InAppBrowserView: View {
    @ObservedObject public var browserCoordinator: WebBrowserCoordinator
    @State private var inputURLText: String = "https://apple.com"

    public init(browserCoordinator: WebBrowserCoordinator? = nil) {
        self.browserCoordinator = browserCoordinator ?? WebBrowserCoordinator.shared
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Address Bar
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.studioAmber)

                    TextField("Enter URL or search...", text: $inputURLText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .font(.studioSecondary)
                        .onSubmit {
                            if !inputURLText.hasPrefix("http") {
                                inputURLText = "https://" + inputURLText
                            }
                            browserCoordinator.currentURLString = inputURLText
                        }

                    Button(action: {
                        browserCoordinator.clearStreams()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.studioSlate)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.obsidianElevated)
                .cornerRadius(12)
                .padding(12)
                .background(Color.obsidianSurface)

                // Web View Surface
                #if os(iOS)
                if let validURL = URL(string: browserCoordinator.currentURLString) {
                    WebViewRepresentable(url: validURL, coordinator: browserCoordinator)
                } else {
                    Text("Invalid URL").foregroundColor(.studioSlate)
                }
                #else
                Text("In-App Browser (iOS / iPadOS Only)").foregroundColor(.studioSlate)
                #endif
            }

            // Floating Unobtrusive Media Sniffer Pill Bar
            if browserCoordinator.showStreamActionSheet, let stream = browserCoordinator.selectedStream {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(.studioAmber)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media Stream Detected")
                                .font(.studioBody)
                                .foregroundColor(.white)
                            Text(stream.title)
                                .font(.studioCaption)
                                .foregroundColor(.studioSlate)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: { browserCoordinator.showStreamActionSheet = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.studioSlate)
                        }
                    }

                    // 3 Action Buttons
                    HStack(spacing: 12) {
                        // 1. Play in App
                        Button(action: {
                            browserCoordinator.playStreamInApp(stream)
                        }) {
                            Label("Play in App", systemImage: "play.fill")
                                .font(.studioCaption)
                                .foregroundColor(.obsidianBackground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.studioAmber)
                                .cornerRadius(10)
                        }

                        // 2. Cast to TV
                        Button(action: {
                            browserCoordinator.castStreamToTV(stream)
                        }) {
                            Label("Cast to TV", systemImage: "tv.fill")
                                .font(.studioCaption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                        }

                        // 3. Background Download
                        Button(action: {
                            _ = BackgroundDownloadManager.shared.startDownload(remoteURL: stream.streamURL, title: stream.title)
                            browserCoordinator.showStreamActionSheet = false
                        }) {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .font(.studioCaption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(16)
                .background(Color.obsidianSurface.opacity(0.95))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.studioAmber.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .shadow(color: Color.black.opacity(0.6), radius: 16, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.obsidianBackground.ignoresSafeArea())
    }
}
