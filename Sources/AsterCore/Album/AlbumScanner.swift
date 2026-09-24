import Foundation
import UniformTypeIdentifiers

/// One photo in an album folder.
public struct PhotoRef: Sendable, Hashable, Identifiable {
    public let url: URL
    /// Path relative to the album folder; the key for this photo's edits.
    public let relativePath: String
    public let fileSize: Int
    public let modified: Date
    public var captureDate: Date?

    public var id: String { relativePath }
    public var fileName: String { url.lastPathComponent }
}

public enum AlbumScanner {
    /// Lists supported images (JPEG, PNG, TIFF) in `folder`, skipping hidden files and AppleDouble `._` files.
    /// - Parameter readCaptureDates: also read EXIF capture dates (≈ 0.2 ms per file).
    public static func scan(folder: URL, recursive: Bool, readCaptureDates: Bool = false) throws -> [PhotoRef] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }

        // Throws a clear error if the folder is missing or unreadable.
        _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: options, errorHandler: { _, _ in true }
        ) else { return [] }

        let rootPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        var photos: [PhotoRef] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard !name.hasPrefix("._"),
                  let type = UTType(filenameExtension: url.pathExtension),
                  ImageSourceInfo.isSupported(type),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : name
            var photo = PhotoRef(
                url: url,
                relativePath: relative,
                fileSize: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            )
            if readCaptureDates {
                photo.captureDate = (try? ImageSourceInfo(url: url))?.captureDate
            }
            photos.append(photo)
        }
        return photos
    }

    /// Finder-style ordering ("IMG_2" before "IMG_10"). Photos without a capture date fall back to modification date.
    public static func sorted(_ photos: [PhotoRef], by sort: PhotoSort) -> [PhotoRef] {
        func byName(_ a: PhotoRef, _ b: PhotoRef) -> Bool {
            a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
        }
        switch sort {
        case .name:
            return photos.sorted(by: byName)
        case .captureDate:
            return photos.sorted {
                let a = $0.captureDate ?? $0.modified, b = $1.captureDate ?? $1.modified
                return a == b ? byName($0, $1) : a < b
            }
        case .modificationDate:
            return photos.sorted { $0.modified == $1.modified ? byName($0, $1) : $0.modified < $1.modified }
        }
    }
}
