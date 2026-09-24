import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AsterCore

@Suite("Naming templates")
struct NamingTemplateTests {
    let values = NamingTemplate.Values(name: "IMG_0042", sequence: 7, recipe: "Instagram 3:4",
                                       date: DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 9,
                                                            day: 1).date!,
                                       width: 1080, height: 1440)

    @Test func rendersTokens() {
        #expect(NamingTemplate("{name}_ig").render(values) == "IMG_0042_ig")
        #expect(NamingTemplate("Smith-{seq:3}-{w}x{h}").render(values) == "Smith-007-1080x1440")
        #expect(NamingTemplate("{date}-{name}").render(values) == "20260901-IMG_0042")
        #expect(NamingTemplate("{date:yyyy}/{recipe}").render(values) == "2026-Instagram 3-4") // separators made safe
    }

    @Test func validation() {
        #expect(NamingTemplate("{name}_web").problems.isEmpty)
        #expect(!NamingTemplate("final").problems.isEmpty)       // every file would share one name
        #expect(!NamingTemplate("{nmae}").problems.isEmpty)      // unknown token
        #expect(!NamingTemplate("a/{name}").problems.isEmpty)    // path separator
        #expect(NamingTemplate("").render(values) == "IMG_0042") // falls back to the source name
    }
}

@Suite("Metadata policies")
struct MetadataPolicyTests {
    /// JPEG with capture date, GPS, camera serial and orientation 6.
    func source(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("src.jpg")
        try Fixtures.write(Fixtures.quadrants(width: 64, height: 32), to: url, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:01 10:30:00",
                                             kCGImagePropertyExifBodySerialNumber: "SN123"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon"],
        ])
        return url
    }

    let profile = PhotographerProfile(creator: "Jane Doe", copyright: "© 2026 Jane Doe", email: "jane@example.com",
                                      website: "https://example.com")

    func export(_ policy: MetadataPolicy, dir: URL) throws -> [CFString: Any] {
        let out = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        try ImageExporter().export(source: source(in: dir), layers: [], settings: ExportSettings(metadata: policy),
                                   profile: profile, to: out)
        return Fixtures.properties(out)
    }

    @Test func socialRemovesLocationAndSerialsButKeepsCredit() throws {
        let props = try export(.social, dir: Fixtures.tempDirectory())
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifBodySerialNumber] == nil)
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:01 10:30:00")
        let iptc = try #require(props[kCGImagePropertyIPTCDictionary] as? [CFString: Any])
        #expect(iptc[kCGImagePropertyIPTCCopyrightNotice] as? String == "© 2026 Jane Doe")
        #expect((iptc[kCGImagePropertyIPTCByline] as? [String]) == ["Jane Doe"])
        #expect(props[kCGImagePropertyOrientation] as? Int == 1)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String == "Canon")
    }

    @Test func clientKeepsEverything() throws {
        let props = try export(.client, dir: Fixtures.tempDirectory())
        #expect(props[kCGImagePropertyGPSDictionary] != nil)
        #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifBodySerialNumber] != nil)
    }

    @Test func copyrightOnlyAndStripAll() throws {
        let dir = try Fixtures.tempDirectory()
        let copyright = try export(MetadataPolicy(mode: .copyrightOnly), dir: dir)
        #expect((copyright[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect((copyright[kCGImagePropertyIPTCDictionary] as? [CFString: Any])?[kCGImagePropertyIPTCCopyrightNotice] != nil)

        let none = try export(.none, dir: dir)
        #expect(none[kCGImagePropertyGPSDictionary] == nil)
        #expect(none[kCGImagePropertyIPTCDictionary] == nil)
        #expect((none[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    }

    @Test func legacyRecipeSettingsDecode() throws {
        let json = #"{"format":{"jpeg":{"quality":0.9}},"render":{"sizeMode":{"original":{}},"allowUpscale":false,"sharpening":"none"},"colorSpace":"sRGB","preserveMetadata":false}"#
        let settings = try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))
        #expect(settings.metadata == .none)
        #expect(settings.colorSpace == .sRGB)
        let social = json.replacingOccurrences(of: "\"preserveMetadata\":false", with: "\"preserveMetadata\":true")
        #expect(try JSONDecoder().decode(ExportSettings.self, from: Data(social.utf8)).metadata == .social)
        let client = social.replacingOccurrences(of: "\"sRGB\"", with: "\"source\"")
        #expect(try JSONDecoder().decode(ExportSettings.self, from: Data(client.utf8)).metadata == .client)
    }
}

@Suite("JPEG size limit")
struct SizeCapTests {
    @Test func fitsUnderTheLimit() throws {
        // Noisy image so JPEG size depends strongly on quality.
        let ctx = Fixtures.context(width: 600, height: 400)
        var rng = SplitMix64(seed: 7)
        for y in stride(from: 0, to: 400, by: 2) {
            for x in stride(from: 0, to: 600, by: 2) {
                let v = Double(rng.next() % 255) / 255
                ctx.setFillColor(CGColor(srgbRed: v, green: 1 - v, blue: v * 0.5, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        let image = ctx.makeImage()!
        let full = try Encoder.jpegData(image, maxQuality: 0.95, maxBytes: .max, metadata: nil)
        let limit = full.count / 3
        let capped = try Encoder.jpegData(image, maxQuality: 0.95, maxBytes: limit, metadata: nil)
        #expect(capped.count <= limit)
        #expect(capped.count > limit / 3, "should use most of the budget")
    }
}

@Suite("Export engine")
struct ExportEngineTests {
    func makeRequest(dir: URL, photoCount: Int = 3, targets: [(Recipe, String)]) throws -> ExportRequest {
        let album = dir.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        for i in 1...photoCount {
            try Fixtures.write(Fixtures.quadrants(width: 2000, height: 1500), to: album.appendingPathComponent("IMG_\(i).jpg"),
                               type: .jpeg)
        }
        let photos = AlbumScanner.sorted(try AlbumScanner.scan(folder: album, recursive: false), by: .name)
        let project = AlbumProject(folder: album, bookmark: nil)
        let exportTargets = try targets.map { recipe, name in
            let folder = dir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return ExportTarget(recipe: recipe, folder: folder)
        }
        return ExportRequest(photos: photos, project: project, targets: exportTargets, sets: [], presets: SizePreset.builtIn,
                             library: LibrarySnapshot(directory: dir, watermarks: []), profile: PhotographerProfile(),
                             maxConcurrency: 2)
    }

    @Test func exportsEveryPhotoForEveryRecipe() async throws {
        let dir = try Fixtures.tempDirectory()
        let recipes = Recipe.starterRecipes()
        var request = try makeRequest(dir: dir, targets: [(recipes[0], "Client"), (recipes[1], "Instagram")])
        request.project.updateEdit(for: "IMG_2.jpg") { $0.isExcluded = true }

        let progress = ProgressLog()
        let report = await ExportEngine().run(request) { progress.append($0) }
        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.written.count == 4) // 2 photos × 2 recipes (IMG_2 excluded)
        #expect(progress.last?.completed == 4)

        let client = try ImageSourceInfo(url: dir.appendingPathComponent("Client/IMG_1.jpg"))
        #expect(client.pixelSize == CGSize(width: 2000, height: 1500))
        let instagram = try ImageSourceInfo(url: dir.appendingPathComponent("Instagram/IMG_1_ig.jpg"))
        #expect(instagram.pixelSize == CGSize(width: 1080, height: 1440)) // 3:4 crop scaled to the platform size
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Instagram/IMG_2_ig.jpg").path))
    }

    @Test func conflictPolicies() async throws {
        let dir = try Fixtures.tempDirectory()
        var recipe = Recipe.starterRecipes()[0]
        let request = try makeRequest(dir: dir, photoCount: 1, targets: [(recipe, "Out")])
        _ = await ExportEngine().run(request)
        _ = await ExportEngine().run(request) // add suffix
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Out/IMG_1-2.jpg").path))

        recipe.conflictPolicy = .skip
        var skipping = request
        skipping.targets[0].recipe = recipe
        let skipped = await ExportEngine().run(skipping)
        #expect(skipped.skipped == 1 && skipped.written.isEmpty)
    }

    @Test func sequenceTemplateNeverCollides() async throws {
        let dir = try Fixtures.tempDirectory()
        var recipe = Recipe(name: "Web", settings: ExportSettings(render: RenderSpec(sizeMode: .longEdge(400))), namingTemplate: "shoot")
        recipe.conflictPolicy = .overwrite
        let request = try makeRequest(dir: dir, photoCount: 3, targets: [(recipe, "Web")])
        let report = await ExportEngine().run(request)
        #expect(Set(report.written.map(\.lastPathComponent)) == ["shoot.jpg", "shoot-2.jpg", "shoot-3.jpg"])
    }

    @Test func cancellationLeavesNoPartialFiles() async throws {
        let dir = try Fixtures.tempDirectory()
        let request = try makeRequest(dir: dir, photoCount: 6, targets: [(Recipe.starterRecipes()[0], "Out")])
        let task = Task { await ExportEngine().run(request) }
        task.cancel()
        let report = await task.value
        #expect(report.cancelled)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Out").path)
        #expect(files.allSatisfy { !$0.hasSuffix(".tmp") })
        #expect(report.written.count < 6)
    }

    @Test func concurrencyShrinksForHugePhotos() {
        #expect(ExportEngine.concurrency(maxPixels: 24e6, limit: 8) == 8)
        #expect(ExportEngine.concurrency(maxPixels: 100e6, limit: 8) == 3)
        #expect(ExportEngine.concurrency(maxPixels: 400e6, limit: 8) == 1)
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ExportProgress] = []
    func append(_ p: ExportProgress) { lock.lock(); items.append(p); lock.unlock() }
    var last: ExportProgress? { lock.lock(); defer { lock.unlock() }; return items.last }
}
