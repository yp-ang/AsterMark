import AppKit
import Foundation
import MetricKit

/// Saves MetricKit reports (hangs, crashes, launch times) to Application Support/AsterMark/Diagnostics.
/// Nothing leaves the Mac; attach the files to a bug report if asked.
// Only holds an immutable folder URL, so sharing it across threads is safe.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    let folder: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AsterMark/Diagnostics", isDirectory: true)
    }()

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { save(payload.jsonRepresentation(), prefix: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { save(payload.jsonRepresentation(), prefix: "diagnostics") }
    }

    private func save(_ data: Data, prefix: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: folder.appendingPathComponent("\(prefix)-\(stamp).json"), options: .atomic)
    }

    func reveal() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
