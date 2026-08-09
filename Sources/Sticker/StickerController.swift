import AppKit

/// 스티커 한 장 = 패널 윈도우 + 이미지 뷰 + 상태.
@MainActor
final class StickerController: NSObject {

    /// 워프를 켜면 늘어난 그림이 잘리지 않게 창에 이 비율만큼 여백을 준다(창 짧은 변 기준).
    /// 그림 크기 대비로 환산하면 ratio / (1 - 2 * ratio) 배 = 약 0.97배까지 담을 수 있다.
    private static let warpMarginRatio: CGFloat = 0.33
    /// 모서리를 끌 수 있는 최대 거리(그림 크기 대비). 위 여백이 감당하는 범위 안에서 최대로 잡았다.
    static let maxWarpOffset: CGFloat = 0.9

    let url: URL
    let image: NSImage
    let window: StickerWindow
    let view: StickerView

    /// 투명한 여백을 뺀, 실제 그림이 놓인 영역(정규화). 핸들은 이 사각형의 네 모서리에 붙는다.
    private(set) var contentBox: NSRect

    /// 네 모서리를 각각 끌어당긴 거리(이미지 크기 대비). 순서는 `StickerView.Handle`의 rawValue.
    private(set) var cornerOffsets: [NSPoint] = Array(repeating: .zero, count: 4)

    /// 워프용 여백을 확보한 상태인지.
    private(set) var warpEnabled = false

    var isWarped: Bool {
        cornerOffsets.contains { abs($0.x) > 0.0001 || abs($0.y) > 0.0001 }
    }

    var flipped: Bool = false {
        didSet { view.needsDisplay = true }
    }

    var isSelected: Bool = false {
        didSet {
            view.needsDisplay = true
            window.invalidateCursorRects(for: view)
        }
    }

    var opacity: Double {
        get { Double(window.alphaValue) }
        set { window.alphaValue = CGFloat(newValue) }
    }

    /// 이미지 둘레의 여백. 워프 중에는 창 크기에 비례해 늘어난다.
    var padding: CGFloat {
        guard warpEnabled else { return StickerView.basePadding }
        return min(window.frame.width, window.frame.height) * Self.warpMarginRatio
    }

    init?(url: URL, frame: NSRect? = nil) {
        guard let image = NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0
        else { return nil }

        self.url = url
        self.image = image
        contentBox = ImageContentBox.compute(for: image)

        let contentRect = frame ?? NSRect(origin: .zero, size: Self.defaultSize(for: image))
        window = StickerWindow(contentRect: contentRect)
        view = StickerView(frame: NSRect(origin: .zero, size: contentRect.size))

        super.init()

        view.controller = self
        view.autoresizingMask = [.width, .height]
        window.contentView = view
    }

    /// 원본 크기를 쓰되 화면을 잡아먹지 않게 줄인다. (여백 포함한 윈도우 크기)
    static func defaultSize(for image: NSImage) -> NSSize {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        let scale = min(1,
                        min(visible.width * 0.35 / image.size.width,
                            visible.height * 0.5 / image.size.height))
        let pad = StickerView.basePadding * 2
        return NSSize(width: image.size.width * scale + pad,
                      height: image.size.height * scale + pad)
    }

    // MARK: - 저장 / 복원

    func snapshot() -> StickerSnapshot {
        let frame = window.frame
        return StickerSnapshot(path: url.path,
                               x: frame.minX, y: frame.minY,
                               width: frame.width, height: frame.height,
                               opacity: opacity,
                               flipped: flipped,
                               warp: cornerOffsets.map { CGPoint(x: $0.x, y: $0.y) },
                               warpEnabled: warpEnabled)
    }

    func restore(from snapshot: StickerSnapshot) {
        opacity = snapshot.opacity
        flipped = snapshot.flipped
        if flipped { contentBox = Self.mirrored(contentBox) }

        // 모서리 네 개 체제로 바뀌기 전에 저장된 파일은 모양 정보를 버린다
        guard let savedWarp = snapshot.warp, savedWarp.count == 4 else { return }
        cornerOffsets = savedWarp.map { NSPoint(x: $0.x, y: $0.y) }
        // 저장된 프레임은 이미 여백을 품고 있으므로 창은 그대로 두고 상태만 되살린다
        warpEnabled = snapshot.warpEnabled ?? isWarped
        view.needsDisplay = true
    }

    // MARK: - 워프

    /// 워프를 시작하기 전에, 그림이 잘리지 않도록 창을 넓히고 그림 위치는 그대로 둔다.
    func makeRoomForWarp() {
        guard !warpEnabled else { return }
        let imageRect = window.frame.insetBy(dx: padding, dy: padding)
        let ratio = Self.warpMarginRatio
        let margin = min(imageRect.width, imageRect.height) * ratio / (1 - 2 * ratio)

        warpEnabled = true
        window.setFrame(NSRect(x: imageRect.minX - margin,
                               y: imageRect.minY - margin,
                               width: imageRect.width + margin * 2,
                               height: imageRect.height + margin * 2),
                        display: true)
        view.needsDisplay = true
    }

    func setCornerOffset(_ offset: NSPoint, at index: Int) {
        guard cornerOffsets.indices.contains(index) else { return }
        let limit = Self.maxWarpOffset
        cornerOffsets[index] = NSPoint(x: min(max(offset.x, -limit), limit),
                                       y: min(max(offset.y, -limit), limit))
        view.needsDisplay = true
    }

    /// 잡아당긴 걸 전부 되돌리고 넓혔던 여백도 반납한다.
    func resetWarp() {
        cornerOffsets = Array(repeating: .zero, count: 4)
        guard warpEnabled else {
            view.needsDisplay = true
            return
        }
        let imageRect = window.frame.insetBy(dx: padding, dy: padding)
        warpEnabled = false
        let pad = StickerView.basePadding
        window.setFrame(NSRect(x: imageRect.minX - pad, y: imageRect.minY - pad,
                               width: imageRect.width + pad * 2,
                               height: imageRect.height + pad * 2),
                        display: true)
        view.needsDisplay = true
        window.invalidateCursorRects(for: view)
    }

    private static func mirrored(_ box: NSRect) -> NSRect {
        NSRect(x: 1 - box.maxX, y: box.minY, width: box.width, height: box.height)
    }

    /// 현재 중심을 유지한 채 윈도우 크기를 바꾼다.
    private func resize(to size: NSSize) {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setFrame(NSRect(x: center.x - size.width / 2,
                               y: center.y - size.height / 2,
                               width: size.width,
                               height: size.height),
                        display: true)
        view.needsDisplay = true
        window.invalidateCursorRects(for: view)
    }

    /// 여백까지 포함한, 지금 이미지 크기에 맞는 창 크기.
    private func windowSize(forImage size: NSSize) -> NSSize {
        guard warpEnabled else {
            let pad = StickerView.basePadding * 2
            return NSSize(width: size.width + pad, height: size.height + pad)
        }
        let ratio = Self.warpMarginRatio
        let margin = min(size.width, size.height) * ratio / (1 - 2 * ratio)
        return NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
    }

    // MARK: - 컨텍스트 메뉴

    func contextMenu() -> NSMenu {
        let menu = NSMenu()

        add(to: menu, "맨 앞으로", #selector(bringToFront))
        add(to: menu, "한 칸 앞으로", #selector(bringForward))
        add(to: menu, "한 칸 뒤로", #selector(sendBackward))
        add(to: menu, "맨 뒤로", #selector(sendToBack))
        menu.addItem(.separator())

        let opacityItem = NSMenuItem(title: "투명도", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [1.0, 0.8, 0.6, 0.4, 0.2] {
            let item = NSMenuItem(title: "\(Int(value * 100))%",
                                  action: #selector(applyOpacity(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(opacity - value) < 0.01 ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let flipItem = add(to: menu, "좌우 반전", #selector(toggleFlip))
        flipItem.state = flipped ? .on : .off

        add(to: menu, "원래 크기로", #selector(resetToDefaultSize))
        add(to: menu, "비율 맞추기", #selector(restoreAspectRatio))

        let resetShape = add(to: menu, "모양 원래대로", #selector(resetShape))
        resetShape.isEnabled = isWarped

        menu.addItem(.separator())
        add(to: menu, "복제", #selector(duplicate))
        add(to: menu, "이 스티커 지우기", #selector(deleteSticker))

        return menu
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - 액션

    @objc private func bringToFront() { StickerManager.shared.move(self, to: .front) }
    @objc private func bringForward() { StickerManager.shared.move(self, to: .forward) }
    @objc private func sendBackward() { StickerManager.shared.move(self, to: .backward) }
    @objc private func sendToBack() { StickerManager.shared.move(self, to: .back) }

    @objc private func applyOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        opacity = value
        StickerManager.shared.scheduleSave()
    }

    @objc private func toggleFlip() {
        flipped.toggle()
        contentBox = Self.mirrored(contentBox)
        // 좌우가 바뀌었으니 모서리별 변위도 짝을 맞바꾸고 x를 뒤집는다
        let offsets = cornerOffsets
        cornerOffsets = [offsets[1], offsets[0], offsets[3], offsets[2]]
            .map { NSPoint(x: -$0.x, y: $0.y) }
        view.needsDisplay = true
        StickerManager.shared.scheduleSave()
    }

    @objc private func resetToDefaultSize() {
        let base = Self.defaultSize(for: image)
        let imageSize = NSSize(width: base.width - StickerView.basePadding * 2,
                               height: base.height - StickerView.basePadding * 2)
        resize(to: windowSize(forImage: imageSize))
        StickerManager.shared.scheduleSave()
    }

    /// 자유 리사이즈로 찌그러진 스티커를 현재 너비 기준으로 원본 비율에 되돌린다.
    @objc private func restoreAspectRatio() {
        let width = max(1, window.frame.width - padding * 2)
        let height = width * image.size.height / image.size.width
        resize(to: windowSize(forImage: NSSize(width: width, height: height)))
        StickerManager.shared.scheduleSave()
    }

    @objc private func resetShape() {
        resetWarp()
        StickerManager.shared.scheduleSave()
    }

    @objc private func duplicate() {
        StickerManager.shared.duplicate(self)
    }

    @objc private func deleteSticker() {
        StickerManager.shared.remove(self)
    }
}
