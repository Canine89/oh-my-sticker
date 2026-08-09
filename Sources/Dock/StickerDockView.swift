import AppKit

/// macOS Dock을 닮은 스티커 팔레트.
/// - 아이콘을 밖으로 끌면 그 자리에 스티커가 놓인다.
/// - 아이콘을 그냥 누르면 올리기/내리기 토글. 올라와 있는 아이콘 아래엔 점이 찍힌다.
/// - 이미지 파일을 독에 떨어뜨리면 보관함에 복사되어 계속 재활용된다.
final class StickerDockView: NSView {

    private let spacing: CGFloat = 12
    private let paddingX: CGFloat = 16
    private let basePadding: CGFloat = 14
    private let maxColumns = 10
    private let emptySize = NSSize(width: 272, height: 116)

    /// 시스템 Dock처럼 높이에 비례해 깊게 둥글린다. 컨트롤러가 이 값으로 배경 마스크를 만든다.
    var cornerRadius: CGFloat { min(bounds.height * 0.30, 34) }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 커서 바로 아래 아이콘이 커지는 배율과, 그 영향이 미치는 가로 범위.
    private let maxScale: CGFloat = 1.28
    private var influence: CGFloat { iconSize * 1.7 }
    /// 아이콘이 부풀 여유. 위아래로 고르게 나눠 담아야 독이 한쪽으로 치우쳐 보이지 않는다.
    private var lift: CGFloat { iconSize * (maxScale - 1) }
    private var paddingTop: CGFloat { basePadding + lift / 2 }
    private var paddingBottom: CGFloat { basePadding + lift / 2 }

    private var iconSize: CGFloat { Settings.dockIconSize }

    var items: [URL] = [] {
        didSet {
            hoverPoint = nil
            needsDisplay = true
            rebuildToolTips()
        }
    }

    var isDropTarget = false {
        didSet { needsDisplay = true }
    }

    private var hoverPoint: NSPoint?
    private var hoverStrength: CGFloat = 0
    private var hoverTimer: Timer?

    private var pressedIndex: Int?
    private var dragStartMouse: NSPoint = .zero
    private var draggedSticker: StickerController?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersDidChange),
                                               name: StickerManager.didChangeNotification,
                                               object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func stickersDidChange() {
        needsDisplay = true
    }

    // MARK: - 레이아웃

    /// 아이콘 개수에 맞춘 독 크기. 컨트롤러가 이 값으로 창을 키우고 줄인다.
    var fittingDockSize: NSSize {
        guard !items.isEmpty else { return emptySize }
        let columns = min(items.count, maxColumns)
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        return NSSize(
            width: paddingX * 2 + CGFloat(columns) * iconSize + CGFloat(columns - 1) * spacing,
            height: paddingTop + paddingBottom + CGFloat(rows) * iconSize + CGFloat(rows - 1) * spacing
        )
    }

    /// 확대 전의 고정 슬롯. 마지막 줄은 가운데로 모은다.
    private func slotRect(at index: Int) -> NSRect {
        let columns = min(max(items.count, 1), maxColumns)
        let row = index / columns
        let column = index % columns
        let countInRow = min(columns, items.count - row * columns)
        let rowWidth = CGFloat(countInRow) * iconSize + CGFloat(countInRow - 1) * spacing
        let startX = (bounds.width - rowWidth) / 2

        let x = startX + CGFloat(column) * (iconSize + spacing)
        let yFromTop = paddingTop + CGFloat(row) * (iconSize + spacing)
        return NSRect(x: x, y: bounds.height - yFromTop - iconSize,
                      width: iconSize, height: iconSize)
    }

    /// 커서와의 가로 거리에 따라 부풀린 크기. 다른 줄의 아이콘은 건드리지 않는다.
    private func scale(for slot: NSRect) -> CGFloat {
        guard let hoverPoint, hoverStrength > 0.01 else { return 1 }
        guard abs(hoverPoint.y - slot.midY) < iconSize else { return 1 }
        let distance = abs(hoverPoint.x - slot.midX)
        guard distance < influence else { return 1 }
        let falloff = 1 - distance / influence
        return 1 + (maxScale - 1) * falloff * falloff * hoverStrength
    }

    /// 슬롯 한가운데를 기준으로 부푼 사각형.
    private func drawRect(at index: Int) -> NSRect {
        let slot = slotRect(at: index)
        let factor = scale(for: slot)
        var rect = slot
        if factor != 1 {
            let width = slot.width * factor
            let height = slot.height * factor
            rect = NSRect(x: slot.midX - width / 2, y: slot.midY - height / 2,
                          width: width, height: height)
        }
        if pressedIndex == index, draggedSticker == nil {
            rect = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
        }
        return rect
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        // 커서가 실제로 닿은 그림 기준으로 고른다. 확대된 아이콘이 우선.
        items.indices
            .sorted { scale(for: slotRect(at: $0)) > scale(for: slotRect(at: $1)) }
            .first { drawRect(at: $0).contains(point) || slotRect(at: $0).contains(point) }
    }

    private func rebuildToolTips() {
        removeAllToolTips()
        for index in items.indices {
            _ = addToolTip(slotRect(at: index),
                           owner: items[index].deletingPathExtension().lastPathComponent,
                           userData: nil)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        rebuildToolTips()
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        drawGlassChrome()

        guard !items.isEmpty else {
            drawEmptyHint()
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .high

        // 크게 그려질 아이콘이 위에 오도록 작은 것부터 그린다
        let order = items.indices.sorted { scale(for: slotRect(at: $0)) < scale(for: slotRect(at: $1)) }
        for index in order {
            drawItem(at: index)
        }
    }

    /// 유리판 느낌 — 위쪽 광택 한 겹과 테두리 한 줄.
    private func drawGlassChrome() {
        let radius = cornerRadius
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let sheen = isDark ? 0.10 : 0.38
        NSGradient(colors: [NSColor.white.withAlphaComponent(sheen),
                            NSColor.white.withAlphaComponent(0.0)])?
            .draw(in: NSRect(x: 0, y: bounds.height - radius * 1.6,
                             width: bounds.width, height: radius * 1.6), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if !isDropTarget {
            let border = isDark
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.black.withAlphaComponent(0.10)
            border.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }

        guard isDropTarget else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        shape.fill()
        let marker = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5),
                                  xRadius: max(4, radius - 4), yRadius: max(4, radius - 4))
        NSColor.controlAccentColor.setStroke()
        marker.lineWidth = 2
        marker.setLineDash([7, 5], count: 2, phase: 0)
        marker.stroke()
    }

    private func drawItem(at index: Int) {
        let url = items[index]
        let rect = drawRect(at: index)
        let isOnScreen = !StickerManager.shared.stickers(for: url).isEmpty
        // 끌어내는 중인 아이콘은 원래 자리를 흐리게 비워둔다
        let alpha: CGFloat = (draggedSticker != nil && pressedIndex == index) ? 0.3 : 1

        if let thumbnail = StickerLibrary.thumbnail(for: url, side: iconSize * maxScale * 1.2) {
            let target = fit(thumbnail.size, in: rect)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.45 : 0.26)
            shadow.shadowBlurRadius = 4 + (rect.width / iconSize - 1) * 12
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            thumbnail.draw(in: target, from: .zero, operation: .sourceOver, fraction: alpha)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.22 * alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        }

        guard isOnScreen else { return }
        // 화면에 올라와 있으면 Dock처럼 슬롯 아래에 점을 찍는다
        let slot = slotRect(at: index)
        let diameter: CGFloat = 5
        let dot = NSRect(x: slot.midX - diameter / 2, y: slot.minY - 11,
                         width: diameter, height: diameter)
        NSColor.labelColor.withAlphaComponent(0.62).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    /// 비율을 지키며 사각형 안에 맞춘다.
    private func fit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let factor = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * factor, height: size.height * factor)
        return NSRect(x: rect.midX - fitted.width / 2,
                      y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    private func drawEmptyHint() {
        let area = bounds.insetBy(dx: 14, dy: 14)
        let outline = NSBezierPath(roundedRect: area, xRadius: 14, yRadius: 14)
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
        outline.lineWidth = 1.5
        outline.setLineDash([6, 5], count: 2, phase: 0)
        outline.stroke()

        let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        if let symbol = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: bounds.midX - size.width / 2,
                                   y: area.maxY - size.height - 14,
                                   width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 2
        let text = NSAttributedString(
            string: "이미지를 여기로 끌어다 놓으면\n보관함에 담깁니다",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        )
        let width = area.width - 12
        let bounding = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin])
        text.draw(with: NSRect(x: area.minX + 6, y: area.minY + 12,
                               width: width, height: bounding.height),
                  options: [.usesLineFragmentOrigin])
    }

    // MARK: - 확대 애니메이션

    private func setHover(_ point: NSPoint?) {
        hoverPoint = point
        animateHover(to: point == nil ? 0 : 1)
        needsDisplay = true
    }

    /// 커서가 들고 날 때 확대가 툭 끊기지 않도록 짧게 보간한다.
    private func animateHover(to target: CGFloat) {
        guard abs(hoverStrength - target) > 0.01 else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let delta = target - self.hoverStrength
                if abs(delta) < 0.02 {
                    self.hoverStrength = target
                    timer.invalidate()
                    self.hoverTimer = nil
                } else {
                    self.hoverStrength += delta * 0.4
                }
                self.needsDisplay = true
            }
        }
    }

    // MARK: - 마우스

    override func mouseMoved(with event: NSEvent) {
        setHover(convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        setHover(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = itemIndex(at: point) else {
            window?.performDrag(with: event)   // 빈 곳을 잡으면 독 자체를 옮긴다
            return
        }
        pressedIndex = index
        dragStartMouse = NSEvent.mouseLocation
        draggedSticker = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = pressedIndex, items.indices.contains(index) else { return }
        let current = NSEvent.mouseLocation

        if draggedSticker == nil {
            let distance = hypot(current.x - dragStartMouse.x, current.y - dragStartMouse.y)
            guard distance > 6 else { return }
            // 끌어내는 순간 스티커를 만들고, 이후 커서를 따라다니게 한다
            draggedSticker = StickerManager.shared.add(url: items[index])
            setHover(nil)
        }

        guard let sticker = draggedSticker else { return }
        let size = sticker.window.frame.size
        sticker.window.setFrameOrigin(NSPoint(x: current.x - size.width / 2,
                                              y: current.y - size.height / 2))
    }

    override func mouseUp(with event: NSEvent) {
        let index = pressedIndex
        let wasDragging = draggedSticker != nil
        pressedIndex = nil
        draggedSticker = nil
        needsDisplay = true

        if wasDragging {
            StickerManager.shared.scheduleSave()
            return
        }
        guard let index, items.indices.contains(index) else { return }
        StickerManager.shared.toggle(url: items[index])
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = itemIndex(at: point) else { return dockMenu() }
        return itemMenu(for: items[index])
    }

    // MARK: - 컨텍스트 메뉴

    private func itemMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        let onScreen = !StickerManager.shared.stickers(for: url).isEmpty

        let toggle = NSMenuItem(title: onScreen ? "화면에서 내리기" : "화면에 올리기",
                                action: #selector(toggleItem(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.representedObject = url
        menu.addItem(toggle)

        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "Finder에서 보기", action: #selector(revealItem(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = url
        menu.addItem(reveal)

        let trash = NSMenuItem(title: "보관함에서 삭제", action: #selector(trashItem(_:)), keyEquivalent: "")
        trash.target = self
        trash.representedObject = url
        menu.addItem(trash)

        menu.addItem(.separator())
        menu.addItem(dockSettingsItem())
        return menu
    }

    private func dockMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "보관함에 이미지 추가…", action: #selector(addImages), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        menu.addItem(dockSettingsItem())
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "독 숨기기", action: #selector(hideDock), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    private func dockSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "아이콘 크기", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for size in [CGFloat(40), 56, 72, 96] {
            let sizeItem = NSMenuItem(title: "\(Int(size)) pt",
                                      action: #selector(changeIconSize(_:)), keyEquivalent: "")
            sizeItem.target = self
            sizeItem.representedObject = size
            sizeItem.state = abs(iconSize - size) < 0.5 ? .on : .off
            submenu.addItem(sizeItem)
        }
        submenu.addItem(.separator())
        let folder = NSMenuItem(title: "보관함 폴더 바꾸기…",
                                action: #selector(changeLibraryFolder), keyEquivalent: "")
        folder.target = self
        submenu.addItem(folder)
        let revealFolder = NSMenuItem(title: "보관함 폴더 열기",
                                      action: #selector(revealLibraryFolder), keyEquivalent: "")
        revealFolder.target = self
        submenu.addItem(revealFolder)
        item.submenu = submenu
        return item
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        StickerManager.shared.toggle(url: url)
        needsDisplay = true
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func trashItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        StickerManager.shared.stickers(for: url).forEach { StickerManager.shared.remove($0) }
        StickerLibrary.moveToTrash(url)
        StickerDockController.shared.reload()
    }

    @objc private func changeIconSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? CGFloat else { return }
        Settings.dockIconSize = size
        StickerDockController.shared.reload()
    }

    @objc private func addImages() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "보관함에 담을 이미지 고르기"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .image]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { StickerLibrary.importFile(at: $0) }
        StickerDockController.shared.reload()
    }

    @objc private func changeLibraryFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "스티커를 보관할 폴더 고르기"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = StickerLibrary.storageFolder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Settings.libraryFolder = folder
        StickerDockController.shared.reload()
    }

    @objc private func revealLibraryFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([StickerLibrary.storageFolder])
    }

    @objc private func hideDock() {
        StickerDockController.shared.hide()
    }

    // MARK: - 드롭 받기 (보관함에 담기)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        let pasteboard = sender.draggingPasteboard

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let imported = urls.compactMap { StickerLibrary.importFile(at: $0) }

        if imported.isEmpty {
            // 브라우저 등에서 파일이 아니라 이미지 데이터만 넘어온 경우
            let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            guard let data, StickerLibrary.importImage(data: data) != nil else {
                NSSound.beep()
                return false
            }
        }

        StickerDockController.shared.reload()
        return true
    }
}
