import Foundation

public enum ImagingError: Error, Equatable, LocalizedError {
    case unreadable(URL)
    case decodeFailed(URL)
    case renderFailed
    case encoderUnavailable(String)
    case encodeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(url):
            "Can't read “\(url.lastPathComponent)”. The file may be missing or not an image."
        case let .decodeFailed(url):
            "Can't decode “\(url.lastPathComponent)”. The file may be damaged or in an unsupported format."
        case .renderFailed:
            "The image couldn't be rendered."
        case let .encoderUnavailable(type):
            "This Mac can't write \(type) files."
        case let .encodeFailed(url):
            "Couldn't save “\(url.lastPathComponent)”. Check the destination folder is writable and has free space."
        }
    }
}
