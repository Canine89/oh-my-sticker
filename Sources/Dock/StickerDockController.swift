import AppKit

/// 스티커 독을 담는 반투명 패널. 스티커보다 한 단계 위에 떠서 항상 손에 닿는다.
final class DockWindow: NSPanel {

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 96),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 독의 표시/위치/보관함 동기화를 맡는다.
@MainActor
final class StickerDockController {
    static let shared = StickerDockController()

    private var window: DockWindow?
    private var dockView: StickerDockView?
    private let watcher = FolderWatcher()
    private var watchedFolder: URL?

    private init() {}

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - 표시

    func show() {
        let window = makeWindowIfNeeded()
        reload()
        window.orderFront(nil)
        Settings.dockVisible = true
        startWatching()
    }

    func hide() {
        window?.orderOut(nil)
        Settings.dockVisible = false
        watcher.stop()
        watchedFolder = nil
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// 보관 폴더를 다시 읽어 아이콘을 새로 그리고, 창 크기를 내용에 맞춘다.
    func reload() {
        guard let window, let dockView else { return }

        StickerLibrary.clearThumbnailCache()
        dockView.items = StickerLibrary.items()

        let size = dockView.fittingDockSize
        let old = window.frame
        let origin = NSPoint(x: old.midX - size.width / 2, y: old.minY)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        applyRoundedMask()
        clampIntoScreen()
        startWatching()
    }

    // MARK: - 스티커를 독에 떨궈 내리기

    /// 화면 좌표가 독 위인지. 스티커를 여기 놓으면 내려간다.
    func contains(screenPoint point: NSPoint) -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.contains(point)
    }

    func setDropHighlight(_ highlighted: Bool) {
        dockView?.isDropTarget = highlighted
    }

    // MARK: - 내부

    private func makeWindowIfNeeded() -> DockWindow {
        if let window { return window }

        let window = DockWindow()
        let view = StickerDockView(frame: NSRect(origin: .zero, size: window.frame.size))
        view.autoresizingMask = [.width, .height]

        // 반투명 배경은 vibrancy 뷰가 맡고, 아이콘은 그 위에 그린다.
        // 둥근 모서리는 layer.cornerRadius가 아니라 maskImage로 준다. cornerRadius만 쓰면
        // behindWindow 백드롭이 마스크 밖까지 새어 모서리에 사각형 잔상이 남는다.
        let background = NSVisualEffectView(frame: view.bounds)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizesSubviews = true
        background.addSubview(view)

        window.contentView = background
        window.setFrameOrigin(Settings.dockOrigin ?? defaultOrigin(for: window.frame.size))

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                Settings.dockOrigin = window.frame.origin
            }
        }

        self.window = window
        self.dockView = view
        return window
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 24)
    }

    /// 아이콘이 늘어나 화면 밖으로 밀려나가지 않게 되돌린다.
    private func clampIntoScreen() {
        guard let window else { return }
        let frame = window.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX + 8), max(visible.maxX - frame.width - 8, visible.minX + 8))
        origin.y = min(max(origin.y, visible.minY + 8), max(visible.maxY - frame.height - 8, visible.minY + 8))
        if origin != frame.origin { window.setFrameOrigin(origin) }
    }

    private func startWatching() {
        let folder = StickerLibrary.storageFolder
        guard watchedFolder != folder else { return }
        watchedFolder = folder
        watcher.start(url: folder) { [weak self] in
            self?.reloadFromWatcher()
        }
    }

    /// 폴더 감시 콜백. 폴더 자체를 다시 열지 않도록 `startWatching`은 건드리지 않는다.
    private func reloadFromWatcher() {
        guard let window, let dockView, window.isVisible else { return }
        StickerLibrary.clearThumbnailCache()
        dockView.items = StickerLibrary.items()
        let size = dockView.fittingDockSize
        let old = window.frame
        window.setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY,
                               width: size.width, height: size.height),
                        display: true)
        applyRoundedMask()
        clampIntoScreen()
    }

    /// 배경 재질과 창 그림자를 모두 둥근 모양으로 오려낸다.
    /// 창 크기가 바뀔 때마다 다시 해줘야 이전 크기의 그림자가 모서리에 남지 않는다.
    private func applyRoundedMask() {
        guard let window, let dockView,
              let background = window.contentView as? NSVisualEffectView else { return }
        background.maskImage = Self.roundedMask(radius: dockView.cornerRadius)
        window.invalidateShadow()
    }

    /// 가운데를 늘려 쓰는 둥근 사각형 마스크.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
