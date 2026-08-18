// [Intent] Unit tests verifying DownloadTaskItem state modeling and progress calculations
import XCTest
@testable import DownloadManagerEngine

final class DownloadManagerEngineTests: XCTestCase {
    func testDownloadTaskStateTransitions() {
        var task = DownloadTaskItem(
            remoteURL: URL(string: "https://example.com/media.mp4")!,
            destinationURL: URL(fileURLWithPath: "/tmp/media.mp4"),
            title: "Sample Video"
        )
        XCTAssertEqual(task.state, .queued)

        task.state = .downloading(progress: 0.5, speedBytesPerSec: 1024 * 1024)
        if case .downloading(let p, _) = task.state {
            XCTAssertEqual(p, 0.5)
        } else {
            XCTFail("Task must be downloading")
        }

        task.state = .completed(fileURL: task.destinationURL)
        if case .completed(let url) = task.state {
            XCTAssertEqual(url.path, "/tmp/media.mp4")
        } else {
            XCTFail("Task must be completed")
        }
    }
}
