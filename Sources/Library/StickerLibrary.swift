import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 스티커 보관함. 독에 떨어뜨린 이미지를 보관 폴더에 복사해두고 계속 재활용한다.
enum StickerLibrary {

    enum Entry {
        case image(URL)
        case folder(URL)
    }

    static let supportedExtensions: Set<String> = [
        "png", "gif", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "pdf"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// 사용자가 따로 폴더를 지정하지 않았을 때 쓰는 기본 보관 폴더.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Brand.supportFolder, isDirectory: true)
            .appendingPathComponent("Stickers", isDirectory: true)
    }

    /// 독이 보여주고, 드롭한 이미지가 복사되는 폴더.
    static var storageFolder: URL {
        let folder = Settings.libraryFolder ?? defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 독에 늘어놓을 이미지들(보관 폴더 최상위, 이름순).
    static func items() -> [URL] {
        entries(in: storageFolder).compactMap {
            if case .image(let url) = $0 { return url }
            return nil
        }
    }

    /// 폴더 한 단계의 내용물. 숨김 파일은 건너뛰고 이름순으로 정렬한다.
    static func entries(in folder: URL) -> [Entry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sorted = contents.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return sorted.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { return .folder(url) }
            return isSupported(url) ? .image(url) : nil
        }
    }

    // MARK: - 보관함에 넣기

    /// 파일을 보관 폴더로 복사한다. 이미 보관 폴더 안이면 그대로 쓴다.
    @discardableResult
    static func importFile(at url: URL) -> URL? {
        guard isSupported(url) else { return nil }
        let folder = storageFolder
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return url
        }
        let destination = uniqueDestination(for: url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// 브라우저 등에서 이미지 데이터만 넘어온 경우. PNG로 정규화해 보관한다.
    @discardableResult
    static func importImage(data: Data, suggestedName: String? = nil) -> URL? {
        let png: Data?
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            png = data
        } else if let rep = NSBitmapImageRep(data: data) {
            png = rep.representation(using: .png, properties: [:])
        } else {
            png = nil
        }
        guard let png else { return nil }

        let base = suggestedName.map { ($0 as NSString).deletingPathExtension } ?? timestampName()
        let destination = uniqueDestination(for: base + ".png")
        do {
            try png.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    static func moveToTrash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// `이름.png`가 이미 있으면 `이름-2.png`, `이름-3.png` … 로 비켜간다.
    private static func uniqueDestination(for fileName: String) -> URL {
        let folder = storageFolder
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static func timestampName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "sticker-\(formatter.string(from: Date()))"
    }

    // MARK: - 썸네일

    private static var thumbnailCache: [String: NSImage] = [:]

    /// 메뉴·독 아이콘용 썸네일. 전체 디코드를 피하려고 ImageIO 썸네일을 쓴다.
    static func thumbnail(for url: URL, side: CGFloat = 18) -> NSImage? {
        let key = "\(url.path)|\(Int(side))"
        if let cached = thumbnailCache[key] { return cached }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(side * scale)
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let aspect = CGFloat(cgImage.width) / CGFloat(max(cgImage.height, 1))
        let size = aspect >= 1
            ? NSSize(width: side, height: side / aspect)
            : NSSize(width: side * aspect, height: side)

        let image = NSImage(cgImage: cgImage, size: size)
        thumbnailCache[key] = image
        return image
    }

    static func clearThumbnailCache() {
        thumbnailCache.removeAll()
    }
}
