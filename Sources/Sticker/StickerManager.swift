import AppKit

/// 화면에 떠 있는 스티커 전체를 관리한다.
/// `stickers` 배열의 순서가 곧 z 순서(index 0 = 맨 뒤, 마지막 = 맨 앞)이며,
/// 순서대로 `orderFront` 를 다시 적용해 쌓임을 강제한다.
@MainActor
final class StickerManager {
    static let shared = StickerManager()

    enum Move { case front, back, forward, backward }

    private(set) var stickers: [StickerController] = []
    private(set) var selected: StickerController?
    private(set) var isHidden = false
    private(set) var isLocked = false

    /// 스티커 목록·선택·표시 상태가 바뀌면 던진다. 메뉴바와 독이 이걸 보고 갱신한다.
    static let didChangeNotification = Notification.Name("StickerManagerDidChange")

    private var saveWorkItem: DispatchWorkItem?
    private var cascadeStep = 0

    private init() {}

    // MARK: - 추가 / 제거

    @discardableResult
    func add(url: URL, frame: NSRect? = nil) -> StickerController? {
        guard let sticker = StickerController(url: url, frame: frame) else {
            NSSound.beep()
            return nil
        }
        if frame == nil {
            sticker.window.setFrameOrigin(nextOrigin(for: sticker.window.frame.size))
        }
        sticker.window.ignoresMouseEvents = isLocked
        stickers.append(sticker)

        if isHidden { setHidden(false) }
        restack()
        select(sticker)
        scheduleSave()
        return sticker
    }

    func addAll(urls: [URL]) {
        urls.forEach { add(url: $0) }
    }

    func duplicate(_ sticker: StickerController) {
        var frame = sticker.window.frame
        frame.origin.x += 24
        frame.origin.y -= 24
        let copy = add(url: sticker.url, frame: frame)
        copy?.opacity = sticker.opacity
        copy?.flipped = sticker.flipped
        scheduleSave()
    }

    func remove(_ sticker: StickerController) {
        guard let index = stickers.firstIndex(where: { $0 === sticker }) else { return }
        stickers.remove(at: index)
        sticker.window.orderOut(nil)
        sticker.window.contentView = nil
        if selected === sticker { selected = nil }
        notifyChange()
        scheduleSave()
    }

    func removeSelected() {
        guard let selected else { NSSound.beep(); return }
        remove(selected)
    }

    func removeAll() {
        stickers.forEach {
            $0.window.orderOut(nil)
            $0.window.contentView = nil
        }
        stickers.removeAll()
        selected = nil
        cascadeStep = 0
        notifyChange()
        scheduleSave()
    }

    /// 같은 이미지로 떠 있는 스티커들.
    func stickers(for url: URL) -> [StickerController] {
        let target = url.standardizedFileURL
        return stickers.filter { $0.url.standardizedFileURL == target }
    }

    /// 독 아이콘 클릭: 안 떠 있으면 올리고, 떠 있으면 전부 내린다.
    func toggle(url: URL) {
        let existing = stickers(for: url)
        if existing.isEmpty {
            add(url: url)
        } else {
            existing.forEach { remove($0) }
        }
    }

    // MARK: - 선택 / z 순서

    func select(_ sticker: StickerController?) {
        guard selected !== sticker else { return }
        selected?.isSelected = false
        selected = sticker
        sticker?.isSelected = true
        notifyChange()
    }

    func move(_ sticker: StickerController, to move: Move) {
        guard let index = stickers.firstIndex(where: { $0 === sticker }) else { return }
        stickers.remove(at: index)
        let target: Int
        switch move {
        case .front:    target = stickers.count
        case .back:     target = 0
        case .forward:  target = min(stickers.count, index + 1)
        case .backward: target = max(0, index - 1)
        }
        stickers.insert(sticker, at: target)
        restack()
        scheduleSave()
    }

    /// 배열 순서대로 다시 쌓는다. 클릭만으로 순서가 바뀌지 않게 조작 때마다 호출한다.
    func restack() {
        guard !isHidden else { return }
        stickers.forEach { $0.window.orderFront(nil) }
        notifyChange()
    }

    // MARK: - 숨기기 / 잠금

    func setHidden(_ hidden: Bool) {
        isHidden = hidden
        if hidden {
            stickers.forEach { $0.window.orderOut(nil) }
            notifyChange()
        } else {
            restack()
        }
    }

    func toggleHidden() { setHidden(!isHidden) }

    /// 잠그면 스티커가 마우스 이벤트를 통과시켜, 아래 앱을 그대로 클릭할 수 있다.
    func setLocked(_ locked: Bool) {
        isLocked = locked
        stickers.forEach { $0.window.ignoresMouseEvents = locked }
        if locked { select(nil) }
        notifyChange()
    }

    func toggleLocked() { setLocked(!isLocked) }

    // MARK: - 배치 저장 / 복원

    func scheduleSave() {
        notifyChange()
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        SessionStore.save(stickers.map { $0.snapshot() })
    }

    func restoreSession() {
        let snapshots = SessionStore.load()
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots where FileManager.default.fileExists(atPath: snapshot.path) {
            guard let sticker = add(url: snapshot.url, frame: snapshot.frame) else { continue }
            sticker.restore(from: snapshot)
        }
        select(nil)
    }

    // MARK: - 내부

    /// 새 스티커가 겹쳐 쌓이지 않게 화면 중앙에서 계단식으로 내려놓는다.
    private func nextOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let visible = screen.visibleFrame
        let offset = CGFloat(cascadeStep % 8) * 28
        cascadeStep += 1

        var origin = NSPoint(x: visible.midX - size.width / 2 + offset,
                             y: visible.midY - size.height / 2 - offset)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return origin
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
