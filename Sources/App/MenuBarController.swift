import AppKit
import UniformTypeIdentifiers

/// 메뉴 막대 아이콘과 그 메뉴. 메뉴를 열 때마다 현재 상태로 다시 만든다.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    /// 보관함 하위 폴더를 따라 내려갈 최대 깊이
    private let maxLibraryDepth = 3

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Brand.menuBarSymbol,
                                   accessibilityDescription: Brand.displayName)
            button.image?.isTemplate = true
            button.toolTip = Brand.displayName
        }

        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateStatusIcon),
                                               name: StickerManager.didChangeNotification,
                                               object: nil)
        updateStatusIcon()
    }

    /// 스티커가 떠 있는지, 잠겨 있는지를 아이콘으로 알려준다.
    @objc private func updateStatusIcon() {
        let manager = StickerManager.shared
        let symbol: String
        if manager.isLocked {
            symbol = "lock.fill"
        } else if manager.stickers.isEmpty || manager.isHidden {
            symbol = Brand.menuBarSymbol
        } else {
            symbol = "seal.fill"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: Brand.displayName)
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: - 메뉴 구성

    func menuNeedsUpdate(_ menu: NSMenu) {
        let manager = StickerManager.shared
        menu.removeAllItems()

        let dockTitle = StickerDockController.shared.isVisible ? "스티커 독 숨기기" : "스티커 독 보이기"
        add(menu, dockTitle, #selector(toggleDock), key: "d", mask: [.command, .option])
        add(menu, "스티커 파일 열기…", #selector(openStickerFiles), key: "o", mask: [.command])
        menu.addItem(libraryItem())
        menu.addItem(.separator())

        let hideTitle = manager.isHidden ? "스티커 모두 보이기" : "스티커 모두 숨기기"
        let hideItem = add(menu, hideTitle, #selector(toggleHidden), key: "h", mask: [.command, .option])
        hideItem.isEnabled = !manager.stickers.isEmpty

        let lockItem = add(menu, "클릭 통과 잠금", #selector(toggleLocked), key: "l", mask: [.command, .option])
        lockItem.state = manager.isLocked ? .on : .off

        menu.addItem(.separator())

        let deleteItem = add(menu, "선택한 스티커 지우기", #selector(removeSelected),
                             key: "\u{8}", mask: [.command, .option])
        deleteItem.isEnabled = manager.selected != nil

        let clearItem = add(menu, "스티커 전부 지우기", #selector(removeAll))
        clearItem.isEnabled = !manager.stickers.isEmpty

        menu.addItem(.separator())

        let statusTitle = manager.stickers.isEmpty
            ? "떠 있는 스티커 없음"
            : "떠 있는 스티커 \(manager.stickers.count)개"
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let restoreItem = add(menu, "종료해도 배치 기억하기", #selector(toggleRestoresSession))
        restoreItem.state = Settings.restoresSession ? .on : .off

        add(menu, "사용법", #selector(showHelp))

        let updateItem = NSMenuItem(title: "업데이트 확인…",
                                    action: #selector(UpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = UpdaterController.shared
        updateItem.isEnabled = UpdaterController.shared.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())
        add(menu, "\(Brand.displayName) 종료", #selector(NSApplication.terminate(_:)), key: "q", mask: [.command])
            .target = NSApp
    }

    private func libraryItem() -> NSMenuItem {
        let item = NSMenuItem(title: "보관함", action: nil, keyEquivalent: "")
        let folder = StickerLibrary.storageFolder

        let submenu = NSMenu()
        fill(submenu, from: folder, depth: 0)
        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "비어 있음 — 독에 이미지를 끌어다 놓으세요",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        submenu.addItem(.separator())
        let change = NSMenuItem(title: "보관함 폴더 바꾸기…", action: #selector(chooseLibraryFolder), keyEquivalent: "")
        change.target = self
        submenu.addItem(change)
        let reveal = NSMenuItem(title: "Finder에서 보기", action: #selector(revealLibraryFolder), keyEquivalent: "")
        reveal.target = self
        submenu.addItem(reveal)

        item.title = "보관함 — \(folder.lastPathComponent)"
        item.submenu = submenu
        return item
    }

    private func fill(_ menu: NSMenu, from folder: URL, depth: Int) {
        for entry in StickerLibrary.entries(in: folder) {
            switch entry {
            case .image(let url):
                let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent,
                                      action: #selector(summonSticker(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = url
                item.image = StickerLibrary.thumbnail(for: url)
                menu.addItem(item)

            case .folder(let url):
                guard depth < maxLibraryDepth else { continue }
                let submenu = NSMenu()
                fill(submenu, from: url, depth: depth + 1)
                guard !submenu.items.isEmpty else { continue }
                let item = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: "")
                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }

    @discardableResult
    private func add(_ menu: NSMenu,
                     _ title: String,
                     _ action: Selector,
                     key: String = "",
                     mask: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - 액션

    @objc private func openStickerFiles() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "화면에 띄울 스티커 고르기"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .image]
        if let folder = Settings.libraryFolder { panel.directoryURL = folder }

        guard panel.runModal() == .OK else { return }
        StickerManager.shared.addAll(urls: panel.urls)
    }

    @objc private func summonSticker(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        StickerManager.shared.add(url: url)
    }

    @objc private func chooseLibraryFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "스티커 PNG가 들어 있는 폴더 고르기"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let folder = Settings.libraryFolder { panel.directoryURL = folder }

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Settings.libraryFolder = folder
        StickerDockController.shared.reload()
    }

    @objc private func revealLibraryFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([StickerLibrary.storageFolder])
    }

    @objc private func toggleDock() { StickerDockController.shared.toggle() }
    @objc private func toggleHidden() { StickerManager.shared.toggleHidden() }
    @objc private func toggleLocked() { StickerManager.shared.toggleLocked() }
    @objc private func removeSelected() { StickerManager.shared.removeSelected() }

    @objc private func removeAll() {
        StickerManager.shared.removeAll()
    }

    @objc private func toggleRestoresSession() {
        Settings.restoresSession.toggle()
    }

    @objc private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "\(Brand.displayName) 사용법"
        alert.informativeText = """
        • 스티커 독: 아이콘을 화면으로 끌어내면 그 자리에 스티커가 놓입니다.
          아이콘을 그냥 누르면 올리기/내리기가 토글됩니다.
        • 화면의 스티커를 독 위로 끌어다 놓으면 내려갑니다(보관함에는 그대로 남습니다).
        • 독에 이미지를 끌어다 놓으면 보관함에 담겨 계속 재활용됩니다.
        • 옮기기: 스티커를 그냥 끕니다.
        • 크기 조정: 스티커를 한 번 클릭해 선택한 뒤 네 모서리 핸들을 끕니다.
          핸들은 투명한 여백을 뺀 그림의 실제 모서리에 붙습니다.
          ⌥(Option)을 누른 채 끌면 비율을 무시하고 늘립니다.
        • 모양 늘리기: 같은 핸들을 ⇧(Shift)를 누른 채 끌면 그 모서리만 잡아당겨져
          모양이 늘어납니다. 되돌리려면 오른쪽 클릭 → "모양 원래대로".
        • 앞뒤 순서·투명도·좌우 반전·복제·삭제: 스티커에서 마우스 오른쪽 버튼.
        • ⌥⌘H  스티커 모두 숨기기 / 다시 보이기
        • ⌥⌘L  클릭 통과 잠금 — 스티커를 화면에 둔 채 아래 앱을 그대로 클릭
        • ⌥⌘⌫  선택한 스티커 지우기
        • ⌥⌘D  스티커 독 보이기/숨기기

        스티커는 발표용 전체 화면 위에도 뜨고, 클릭해도 발표 중인 앱의 포커스를 빼앗지 않습니다.
        """
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}
