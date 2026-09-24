import CoreGraphics
import Foundation
import ImageIO

/// The photographer's credit, embedded on export (Settings ▸ Photographer).
public struct PhotographerProfile: Codable, Sendable, Hashable {
    public var creator: String
    public var copyright: String
    public var email: String
    public var website: String
    public var usageTerms: String

    public init(creator: String = "", copyright: String = "", email: String = "", website: String = "", usageTerms: String = "") {
        self.creator = creator
        self.copyright = copyright
        self.email = email
        self.website = website
        self.usageTerms = usageTerms
    }

    public var isEmpty: Bool { [creator, copyright, email, website, usageTerms].allSatisfy(\.isEmpty) }
}

/// What metadata an export carries.
public struct MetadataPolicy: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        /// Everything from the source (EXIF, IPTC, XMP), minus anything removed below.
        case keepAll
        /// Only capture date, credit and copyright.
        case copyrightOnly
        /// Nothing but the colour profile.
        case stripAll
    }

    public var mode: Mode
    /// GPS coordinates and place names.
    public var removeLocation: Bool
    /// Camera and lens serial numbers, owner name.
    public var removeCameraSerials: Bool
    /// Add the photographer profile (creator, copyright, contact).
    public var embedProfile: Bool

    public init(mode: Mode = .keepAll, removeLocation: Bool = false, removeCameraSerials: Bool = false, embedProfile: Bool = true) {
        self.mode = mode
        self.removeLocation = removeLocation
        self.removeCameraSerials = removeCameraSerials
        self.embedProfile = embedProfile
    }

    /// Client deliveries: keep everything, add credit.
    public static let client = MetadataPolicy()
    /// Public posts: no location or serial numbers (decision D7).
    public static let social = MetadataPolicy(removeLocation: true, removeCameraSerials: true)
    public static let none = MetadataPolicy(mode: .stripAll, embedProfile: false)
}

public enum MetadataWriter {
    static let locationNames: Set<String> = [
        "photoshop:City", "photoshop:State", "photoshop:Country", "Iptc4xmpCore:Location", "Iptc4xmpCore:CountryCode",
    ]
    static let serialNames: Set<String> = [
        "exifEX:BodySerialNumber", "exifEX:LensSerialNumber", "exifEX:CameraOwnerName", "aux:SerialNumber",
        "aux:LensSerialNumber", "aux:OwnerName",
    ]
    static let copyrightNames: Set<String> = [
        "dc:rights", "dc:creator", "photoshop:Credit", "photoshop:DateCreated", "xmpRights:UsageTerms",
        "xmpRights:Marked", "xmpRights:WebStatement",
    ]

    /// Builds the metadata for an export from the source file, the policy and the profile.
    /// Orientation is reset to upright (pixels are already rotated) and pixel dimensions updated.
    public static func metadata(
        from source: URL,
        policy: MetadataPolicy,
        profile: PhotographerProfile,
        outputSize: CGSize
    ) -> CGImageMetadata {
        let sourceMetadata = CGImageSourceCreateWithURL(source as CFURL, nil)
            .flatMap { CGImageSourceCopyMetadataAtIndex($0, 0, nil) }
        let metadata: CGMutableImageMetadata

        switch policy.mode {
        case .keepAll:
            metadata = sourceMetadata.flatMap(CGImageMetadataCreateMutableCopy) ?? CGImageMetadataCreateMutable()
        case .copyrightOnly:
            metadata = CGImageMetadataCreateMutable()
            if let sourceMetadata {
                for path in copyrightNames {
                    if let tag = CGImageMetadataCopyTagWithPath(sourceMetadata, nil, path as CFString) {
                        CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
                    }
                }
            }
        case .stripAll:
            return CGImageMetadataCreateMutable()
        }

        if policy.removeLocation || policy.removeCameraSerials {
            var remove: [String] = []
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, _ in
                let name = path as String
                if policy.removeLocation, name.contains("GPS") || locationNames.contains(name) { remove.append(name) }
                if policy.removeCameraSerials, serialNames.contains(name) { remove.append(name) }
                return true
            }
            for path in remove { CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
        }

        CGImageMetadataSetValueWithPath(metadata, nil, "tiff:Orientation" as CFString, "1" as CFString)
        CGImageMetadataSetValueWithPath(metadata, nil, "exif:PixelXDimension" as CFString, "\(Int(outputSize.width))" as CFString)
        CGImageMetadataSetValueWithPath(metadata, nil, "exif:PixelYDimension" as CFString, "\(Int(outputSize.height))" as CFString)
        CGImageMetadataSetValueWithPath(metadata, nil, "xmp:CreatorTool" as CFString, "AsterMark" as CFString)

        if policy.embedProfile {
            embed(profile, in: metadata)
        }
        return metadata
    }

    static func embed(_ profile: PhotographerProfile, in metadata: CGMutableImageMetadata) {
        if !profile.creator.isEmpty,
           let tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore,
                                              "creator" as CFString, .arrayOrdered, [profile.creator] as CFArray) {
            CGImageMetadataSetTagWithPath(metadata, nil, "dc:creator" as CFString, tag)
            CGImageMetadataSetValueWithPath(metadata, nil, "photoshop:Credit" as CFString, profile.creator as CFString)
        }
        if !profile.copyright.isEmpty {
            CGImageMetadataSetValueWithPath(metadata, nil, "dc:rights" as CFString, profile.copyright as CFString)
            CGImageMetadataSetValueWithPath(metadata, nil, "xmpRights:Marked" as CFString, "True" as CFString)
        }
        if !profile.usageTerms.isEmpty {
            CGImageMetadataSetValueWithPath(metadata, nil, "xmpRights:UsageTerms" as CFString, profile.usageTerms as CFString)
        }
        if !profile.website.isEmpty {
            CGImageMetadataSetValueWithPath(metadata, nil, "xmpRights:WebStatement" as CFString, profile.website as CFString)
        }
        if !profile.email.isEmpty || !profile.website.isEmpty {
            // IPTC Core contact info lives in its own namespace.
            let ns = "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/" as CFString
            CGImageMetadataRegisterNamespaceForPrefix(metadata, ns, "Iptc4xmpCore" as CFString, nil)
            if !profile.email.isEmpty {
                CGImageMetadataSetValueWithPath(metadata, nil, "Iptc4xmpCore:CreatorContactInfo.Iptc4xmpCore:CiEmailWork" as CFString,
                                                profile.email as CFString)
            }
            if !profile.website.isEmpty {
                CGImageMetadataSetValueWithPath(metadata, nil, "Iptc4xmpCore:CreatorContactInfo.Iptc4xmpCore:CiUrlWork" as CFString,
                                                profile.website as CFString)
            }
        }
    }
}
