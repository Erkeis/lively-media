// [Intent] Embedded async Swift HTTP server handling Web Wi-Fi file uploads and HTTP 206 Range streaming for Chromecast
import Foundation
import FlyingFox
import CoreStorage

public final class WebTransferServer: @unchecked Sendable {
    private let server: HTTPServer
    private let targetDirectory: URL
    private var isRunning: Bool = false

    public init(port: UInt16 = 8080, targetDirectory: URL) {
        self.targetDirectory = targetDirectory
        self.server = HTTPServer(port: port)
        setupRoutes()
    }

    private func setupRoutes() {
        // 1. Web UI Root
        Task {
            await server.appendRoute("GET /") { _ in
                HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "text/html; charset=utf-8"],
                    body: WebAssets.indexHTML.data(using: .utf8) ?? Data()
                )
            }

            // 2. File Listing API
            await server.appendRoute("GET /api/files") { [targetDirectory] _ in
                let fileManager = FileManager.default
                guard let files = try? fileManager.contentsOfDirectory(at: targetDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
                    return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: "[]".data(using: .utf8)!)
                }

                let items = files.compactMap { url -> [String: Any]? in
                    guard !url.lastPathComponent.hasPrefix(".") else { return nil }
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return ["name": url.lastPathComponent, "size": size]
                }

                let jsonData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
                return HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "application/json"],
                    body: jsonData
                )
            }

            // 3. Upload API
            await server.appendRoute("POST /api/upload") { [targetDirectory] request in
                let body = try await request.bodyData
                // Extract filename from header or assign default
                let filename = request.headers[HTTPHeader("X-File-Name")] ?? "upload_\(UUID().uuidString).bin"
                let destinationURL = targetDirectory.appendingPathComponent(filename)

                do {
                    try body.write(to: destinationURL)
                    return HTTPResponse(statusCode: .ok, body: "{\"status\":\"success\"}".data(using: .utf8)!)
                } catch {
                    return HTTPResponse(statusCode: .internalServerError, body: "{\"error\":\"\(error.localizedDescription)\"}".data(using: .utf8)!)
                }
            }

            // 4. HTTP Range 206 Streaming for Chromecast & Remote Players
            await server.appendRoute("GET /stream/*") { [targetDirectory] request in
                let path = request.path.replacingOccurrences(of: "/stream/", with: "")
                let fileURL = targetDirectory.appendingPathComponent(path)

                guard FileManager.default.fileExists(atPath: fileURL.path),
                      let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
                    return HTTPResponse(statusCode: .notFound)
                }
                defer { try? fileHandle.close() }

                let fileSize = (try? fileHandle.seekToEnd()) ?? 0
                var headers: [HTTPHeader: String] = [
                    .acceptRanges: "bytes",
                    .contentType: "video/mp4"
                ]

                if let rangeHeader = request.headers[HTTPHeader("Range")],
                   rangeHeader.hasPrefix("bytes=") {
                    let rangeString = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                    let parts = rangeString.split(separator: "-", omittingEmptySubsequences: false)

                    let start = UInt64(parts.first ?? "0") ?? 0
                    let end = parts.count > 1 && !parts[1].isEmpty ? (UInt64(parts[1]) ?? (fileSize - 1)) : (fileSize - 1)
                    let length = (end - start) + 1

                    try? fileHandle.seek(toOffset: start)
                    let chunkData = fileHandle.readData(ofLength: Int(length))

                    headers[.contentRange] = "bytes \(start)-\(end)/\(fileSize)"
                    headers[.contentLength] = "\(length)"

                    return HTTPResponse(
                        statusCode: .partialContent,
                        headers: headers,
                        body: chunkData
                    )
                } else {
                    try? fileHandle.seek(toOffset: 0)
                    let fullData = fileHandle.readDataToEndOfFile()
                    headers[.contentLength] = "\(fileSize)"
                    return HTTPResponse(statusCode: .ok, headers: headers, body: fullData)
                }
            }
        }
    }

    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        try await server.run()
    }

    public func stop() async {
        guard isRunning else { return }
        await server.stop()
        isRunning = false
    }
}
