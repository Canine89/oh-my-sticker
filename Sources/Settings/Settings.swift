import AppKit

/// UserDefaults 기반 앱 설정.
enum Settings {
    private enum Key {
        static let libraryFolder = "libraryFolderPath"
        static let restoresSession = "restoresSession"
        static let dockVisible = "dockVisible"
        static let dockOrigin = "dockOrigin"
        static let dockIconSize = "dockIconSize"
    }

    private static let defaults = UserDefaults.standard

    /// 스티커 독이 보여줄 보관 폴더. `nil`이면 앱이 관리하는 기본 폴더를 쓴다.
    static var libraryFolder: URL? {
        get {
            guard let path = defaults.string(forKey: Key.libraryFolder) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set { defaults.set(newValue?.path, forKey: Key.libraryFolder) }
    }

    /// 앱을 다시 켰을 때 마지막 스티커 배치를 되살릴지.
    static var restoresSession: Bool {
        get {
            if defaults.object(forKey: Key.restoresSession) == nil { return true }
            return defaults.bool(forKey: Key.restoresSession)
        }
        set { defaults.set(newValue, forKey: Key.restoresSession) }
    }

    /// 스티커 독을 화면에 띄워둘지.
    static var dockVisible: Bool {
        get {
            if defaults.object(forKey: Key.dockVisible) == nil { return true }
            return defaults.bool(forKey: Key.dockVisible)
        }
        set { defaults.set(newValue, forKey: Key.dockVisible) }
    }

    /// 사용자가 옮겨 둔 독 위치. 없으면 주 화면 아래쪽 가운데.
    static var dockOrigin: NSPoint? {
        get {
            guard let string = defaults.string(forKey: Key.dockOrigin) else { return nil }
            return NSPointFromString(string)
        }
        set { defaults.set(newValue.map { NSStringFromPoint($0) }, forKey: Key.dockOrigin) }
    }

    static var dockIconSize: CGFloat {
        get {
            let value = defaults.double(forKey: Key.dockIconSize)
            return value >= 32 ? CGFloat(value) : 56
        }
        set { defaults.set(Double(newValue), forKey: Key.dockIconSize) }
    }
}

/// 화면에 떠 있는 스티커 한 장의 저장 표현.
struct StickerSnapshot: Codable {
    var path: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var opacity: Double
    var flipped: Bool
    /// 모양 조작점과 잡아당긴 정도. 예전 버전이 남긴 파일에는 없다.
    var anchors: [CGPoint]?
    var warp: [CGPoint]?
    var warpEnabled: Bool?

    var url: URL { URL(fileURLWithPath: path) }
    var frame: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

/// 마지막 배치를 Application Support에 JSON으로 남긴다. 배열 순서가 곧 z 순서(뒤 → 앞).
enum SessionStore {

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Brand.supportFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("session.json")
    }

    static func save(_ snapshots: [StickerSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> [StickerSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([StickerSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }
}
