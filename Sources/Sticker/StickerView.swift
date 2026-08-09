import AppKit

/// 스티커 이미지와 네 모서리 핸들을 그리고, 이동 / 크기 조정 / 모서리 잡아당기기를 처리한다.
///
/// 핸들은 하나뿐이다. 그냥 끌면 크기 조정, `⇧`를 누른 채 끌면 그 모서리만 잡아당겨 모양이 늘어난다.
/// 핸들 자리는 투명한 여백을 뺀 실제 그림의 네 모서리다.
final class StickerView: NSView {

    enum Handle: Int, CaseIterable {
        // 폴리곤을 이루도록 좌하 → 우하 → 우상 → 좌상 순서
        case bottomLeft = 0, bottomRight, topRight, topLeft

        /// 코너 방향 부호 (x, y)
        var sign: (x: CGFloat, y: CGFloat) {
            switch self {
            case .bottomLeft:  return (-1, -1)
            case .bottomRight: return (1, -1)
            case .topRight:    return (1, 1)
            case .topLeft:     return (-1, 1)
            }
        }

        /// 크기를 조정할 때 못 박아두는 반대편 모서리
        var opposite: Handle {
            switch self {
            case .bottomLeft:  return .topRight
            case .bottomRight: return .topLeft
            case .topRight:    return .bottomLeft
            case .topLeft:     return .bottomRight
            }
        }
    }

    /// 워프하지 않을 때 이미지 둘레에 두는 여백.
    static let basePadding: CGFloat = 10

    private let handleSize: CGFloat = 10
    private let minSide: CGFloat = 48

    weak var controller: StickerController?

    private var activeHandle: Handle?
    private var isWarping = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var dragStartContent: NSSize = .zero
    private var dragFixedPoint: NSPoint = .zero      // 화면 좌표
    private var dragStartOffset: NSPoint = .zero
    private var didDrag = false
    private var pushedCursor = false
    private var shiftHeld = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var padding: CGFloat { controller?.padding ?? Self.basePadding }

    /// 여백을 뺀, 이미지 전체가 놓이는 사각형.
    var imageRect: NSRect {
        bounds.insetBy(dx: padding, dy: padding)
    }

    /// 그중 실제로 그림이 그려진 사각형. 핸들은 여기 모서리에 붙는다.
    var contentRect: NSRect {
        let rect = imageRect
        let box = controller?.contentBox ?? NSRect(x: 0, y: 0, width: 1, height: 1)
        return NSRect(x: rect.minX + box.minX * rect.width,
                      y: rect.minY + box.minY * rect.height,
                      width: box.width * rect.width,
                      height: box.height * rect.height)
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let context = NSGraphicsContext.current else { return }
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }

        context.imageInterpolation = .high

        if controller.isWarped {
            drawWarpedImage(in: rect, controller: controller)
        } else {
            drawImage(in: rect, controller: controller)
        }

        guard controller.isSelected else { return }
        drawSelectionChrome()
    }

    /// 있는 그대로 한 번에 그린다.
    private func drawImage(in rect: NSRect, controller: StickerController) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        applyFlip(in: rect, controller: controller)
        controller.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGraphicsState()
    }

    /// 네 모서리와 그 무게중심으로 부채꼴 삼각형을 만들고, 삼각형마다 아핀 변환으로 늘려 그린다.
    private func drawWarpedImage(in rect: NSRect, controller: StickerController) {
        guard let context = NSGraphicsContext.current else { return }
        let cgContext = context.cgContext

        let source = Handle.allCases.map { cornerPoint($0, warped: false) }
        let target = Handle.allCases.map { cornerPoint($0, warped: true) }
        let sourceCenter = centroid(source)
        let targetCenter = centroid(target)

        for index in source.indices {
            let next = (index + 1) % source.count
            let sourceTriangle = [sourceCenter, source[index], source[next]]
            // 이웃한 삼각형끼리 1px 남짓 겹치게 해서 경계에 실틈이 보이지 않게 한다
            let targetTriangle = expand([targetCenter, target[index], target[next]], by: 1.2)
            guard let transform = affineTransform(from: sourceTriangle, to: targetTriangle) else { continue }

            context.saveGraphicsState()
            let path = CGMutablePath()
            path.move(to: targetTriangle[0])
            path.addLine(to: targetTriangle[1])
            path.addLine(to: targetTriangle[2])
            path.closeSubpath()
            cgContext.addPath(path)
            cgContext.clip()
            cgContext.concatenate(transform)
            applyFlip(in: rect, controller: controller)
            controller.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.restoreGraphicsState()
        }
    }

    private func applyFlip(in rect: NSRect, controller: StickerController) {
        guard controller.flipped, let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.translateBy(x: rect.midX, y: 0)
        cgContext.scaleBy(x: -1, y: 1)
        cgContext.translateBy(x: -rect.midX, y: 0)
    }

    /// 선택 테두리와 네 모서리 핸들. 늘어난 스티커에서는 테두리도 같이 늘어난다.
    private func drawSelectionChrome() {
        let corners = Handle.allCases.map { cornerPoint($0, warped: true) }

        let outline = NSBezierPath()
        outline.move(to: corners[0])
        for point in corners.dropFirst() { outline.line(to: point) }
        outline.close()
        outline.lineWidth = 1.5
        outline.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        for handle in Handle.allCases {
            let path = NSBezierPath(roundedRect: handleRect(for: handle), xRadius: 2, yRadius: 2)
            // Shift를 누르고 있으면 "지금 끌면 모양이 늘어난다"는 뜻으로 핸들이 채워진다
            if shiftHeld {
                NSColor.controlAccentColor.setFill()
                path.fill()
                NSColor.white.setStroke()
            } else {
                NSColor.white.setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
            }
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    // MARK: - 좌표 계산

    /// 그림 모서리의 자리. `warped`면 잡아당긴 만큼 옮겨진 위치를 준다.
    private func cornerPoint(_ handle: Handle, warped: Bool) -> NSPoint {
        let content = contentRect
        var point = NSPoint(x: handle.sign.x > 0 ? content.maxX : content.minX,
                            y: handle.sign.y > 0 ? content.maxY : content.minY)
        guard warped, let controller,
              controller.cornerOffsets.indices.contains(handle.rawValue) else { return point }
        let offset = controller.cornerOffsets[handle.rawValue]
        let rect = imageRect
        point.x += offset.x * rect.width
        point.y += offset.y * rect.height
        return point
    }

    private func handleRect(for handle: Handle) -> NSRect {
        let point = cornerPoint(handle, warped: true)
        return NSRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2,
                      width: handleSize, height: handleSize)
    }

    private func handle(at point: NSPoint) -> Handle? {
        Handle.allCases.first { handleRect(for: $0).insetBy(dx: -5, dy: -5).contains(point) }
    }

    /// 워프하려면 창을 그림의 3배 가까이 넓혀야 한다. 그 빈 여백까지 클릭을 먹으면
    /// 뒤에 있는 스티커를 집을 수 없으니, 실제로 그림이 놓인 자리에서만 마우스를 받는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller, controller.warpEnabled else { return super.hitTest(point) }
        let local = superview.map { convert(point, from: $0) } ?? point

        let corners = Handle.allCases.map { cornerPoint($0, warped: true) }
        let shape = NSBezierPath()
        shape.move(to: corners[0])
        for corner in corners.dropFirst() { shape.line(to: corner) }
        shape.close()

        // 테두리 바로 바깥의 핸들도 잡을 수 있어야 한다
        if shape.contains(local) { return self }
        return handle(at: local) != nil ? self : nil
    }

    private func centroid(_ points: [NSPoint]) -> NSPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(NSPoint.zero) { NSPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return NSPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func expand(_ triangle: [NSPoint], by amount: CGFloat) -> [NSPoint] {
        let center = centroid(triangle)
        return triangle.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = hypot(dx, dy)
            guard length > 0.001 else { return point }
            return NSPoint(x: point.x + dx / length * amount,
                           y: point.y + dy / length * amount)
        }
    }

    /// 세 점의 대응으로 정해지는 아핀 변환.
    private func affineTransform(from source: [NSPoint], to target: [NSPoint]) -> CGAffineTransform? {
        let (x0, y0) = (source[0].x, source[0].y)
        let dx1 = source[1].x - x0, dy1 = source[1].y - y0
        let dx2 = source[2].x - x0, dy2 = source[2].y - y0
        let determinant = dx1 * dy2 - dx2 * dy1
        guard abs(determinant) > 0.0001 else { return nil }

        let (u0, v0) = (target[0].x, target[0].y)
        let du1 = target[1].x - u0, dv1 = target[1].y - v0
        let du2 = target[2].x - u0, dv2 = target[2].y - v0

        let a = (du1 * dy2 - du2 * dy1) / determinant
        let b = (dv1 * dy2 - dv2 * dy1) / determinant
        let c = (dx1 * du2 - dx2 * du1) / determinant
        let d = (dx1 * dv2 - dx2 * dv1) / determinant
        return CGAffineTransform(a: a, b: b, c: c, d: d,
                                 tx: u0 - a * x0 - c * y0,
                                 ty: v0 - b * x0 - d * y0)
    }

    // MARK: - 커서 / 추적

    override func resetCursorRects() {
        discardCursorRects()
        guard let controller else { return }
        addCursorRect(bounds, cursor: .openHand)
        guard controller.isSelected else { return }
        for handle in Handle.allCases {
            addCursorRect(handleRect(for: handle).insetBy(dx: -5, dy: -5), cursor: .crosshair)
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
    }

    /// 창이 키 윈도우가 아니라 flagsChanged를 못 받으므로, 커서가 움직일 때 Shift 상태를 살핀다.
    private func updateShiftState(_ flags: NSEvent.ModifierFlags) {
        let held = flags.contains(.shift)
        guard held != shiftHeld else { return }
        shiftHeld = held
        if controller?.isSelected == true { needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) {
        updateShiftState(event.modifierFlags)
    }

    override func mouseEntered(with event: NSEvent) {
        updateShiftState(event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        updateShiftState([])
    }

    // MARK: - 마우스

    override func mouseDown(with event: NSEvent) {
        guard let controller, let window else { return }
        let manager = StickerManager.shared
        let wasSelected = controller.isSelected
        updateShiftState(event.modifierFlags)
        manager.select(controller)
        manager.restack()   // 클릭만으로 z 순서가 바뀌지 않게 배열 순서를 다시 강제한다

        let point = convert(event.locationInWindow, from: nil)
        didDrag = false
        isWarping = false
        // 이미 선택된 스티커에서만 핸들이 보이므로, 그때만 핸들 조작으로 해석한다
        activeHandle = wasSelected ? handle(at: point) : nil
        dragStartMouse = NSEvent.mouseLocation

        if let handle = activeHandle {
            if event.modifierFlags.contains(.shift) {
                // Shift + 핸들 = 그 모서리만 잡아당겨 모양 늘리기
                isWarping = true
                controller.makeRoomForWarp()   // 늘어날 자리를 먼저 확보한다
                dragStartOffset = controller.cornerOffsets[handle.rawValue]
            } else {
                dragStartFrame = window.frame
                dragStartContent = contentRect.size
                // 반대편 모서리를 화면에 못 박아두고 그쪽을 기준으로 확대·축소한다
                dragFixedPoint = window.convertPoint(toScreen: cornerPoint(handle.opposite, warped: false))
            }
            return
        }

        dragStartFrame = window.frame
        NSCursor.closedHand.push()
        pushedCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouse.x
        let dy = current.y - dragStartMouse.y
        if !didDrag, abs(dx) < 1, abs(dy) < 1 { return }
        didDrag = true

        guard let handle = activeHandle else {
            window.setFrameOrigin(NSPoint(x: dragStartFrame.minX + dx,
                                          y: dragStartFrame.minY + dy))
            // 독 위로 끌고 가면 "내려놓기" 표시를 켠다
            StickerDockController.shared.setDropHighlight(
                StickerDockController.shared.contains(screenPoint: current))
            return
        }

        if isWarping {
            guard let controller else { return }
            let rect = imageRect
            guard rect.width > 0, rect.height > 0 else { return }
            controller.setCornerOffset(NSPoint(x: dragStartOffset.x + dx / rect.width,
                                               y: dragStartOffset.y + dy / rect.height),
                                       at: handle.rawValue)
            window.invalidateCursorRects(for: self)
            return
        }

        resize(handle: handle, dx: dx, dy: dy, freeform: event.modifierFlags.contains(.option))
    }

    /// 여백을 뺀 그림 크기를 기준으로 배율을 구하고, 창 전체에 같은 배율을 먹인다.
    private func resize(handle: Handle, dx: CGFloat, dy: CGFloat, freeform: Bool) {
        guard let window, dragStartContent.width > 0, dragStartContent.height > 0 else { return }
        let sign = handle.sign
        var scaleX: CGFloat
        var scaleY: CGFloat

        if freeform {
            // Option: 비율을 깨고 가로/세로를 따로 늘린다
            scaleX = 1 + sign.x * dx / dragStartContent.width
            scaleY = 1 + sign.y * dy / dragStartContent.height
        } else {
            // 기본: 마우스 이동량을 대각선에 투영해 원본 비율을 유지한다
            let diagonal = hypot(dragStartContent.width, dragStartContent.height)
            let unitX = sign.x * dragStartContent.width / diagonal
            let unitY = sign.y * dragStartContent.height / diagonal
            let scale = 1 + (dx * unitX + dy * unitY) / diagonal
            scaleX = scale
            scaleY = scale
        }

        scaleX = max(scaleX, minSide / dragStartContent.width)
        scaleY = max(scaleY, minSide / dragStartContent.height)

        let frame = dragStartFrame
        window.setFrame(NSRect(x: dragFixedPoint.x + (frame.minX - dragFixedPoint.x) * scaleX,
                               y: dragFixedPoint.y + (frame.minY - dragFixedPoint.y) * scaleY,
                               width: frame.width * scaleX,
                               height: frame.height * scaleY),
                        display: true)
        needsDisplay = true
        window.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
        let wasMoving = activeHandle == nil
        activeHandle = nil
        isWarping = false

        // 독 위에 떨어뜨렸으면 화면에서 내린다. 보관함에는 그대로 남는다.
        if didDrag, wasMoving,
           StickerDockController.shared.contains(screenPoint: NSEvent.mouseLocation),
           let controller {
            StickerDockController.shared.setDropHighlight(false)
            // 보관함 밖에서 온 스티커라면 이참에 보관함에 담아 다음에도 쓰게 한다
            let url = controller.url
            StickerManager.shared.remove(controller)
            if StickerLibrary.importFile(at: url) != nil {
                StickerDockController.shared.reload()
            }
            return
        }

        StickerDockController.shared.setDropHighlight(false)
        if didDrag { StickerManager.shared.scheduleSave() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let controller else { return nil }
        StickerManager.shared.select(controller)
        return controller.contextMenu()
    }
}
