import AppKit
import Carbon.HIToolbox

/// 전역 단축키 등록기.
/// Carbon `RegisterEventHotKey` 기반이라 접근성 권한이 필요 없고, 발표 중인 앱에 포커스가 있어도 동작한다.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    /// - Parameters:
    ///   - keyCode: Carbon 가상 키코드 (예: `kVK_ANSI_L`)
    ///   - modifiers: `cmdKey`, `optionKey`, `shiftKey`, `controlKey` 조합
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @MainActor @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C53544B), id: id) // 'LSTK'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        handlers[id] = handler
        refs.append(ref)
        return true
    }

    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventHandler, 1, &spec, nil, nil)
    }
}

private func hotkeyEventHandler(_ callRef: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            HotkeyManager.shared.fire(id: id)
        }
    }
    return noErr
}
