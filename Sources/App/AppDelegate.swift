import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBar = MenuBarController()
        registerHotkeys()
        _ = UpdaterController.shared      // 시작과 함께 백그라운드 업데이트 확인

        if Settings.restoresSession {
            StickerManager.shared.restoreSession()
        }
        if Settings.dockVisible {
            StickerDockController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Settings.restoresSession {
            StickerManager.shared.saveNow()
        } else {
            SessionStore.save([])
        }
        HotkeyManager.shared.stop()
    }

    /// 발표 중인 앱에 포커스가 있어도 듣는 전역 단축키. 접근성 권한이 필요 없다.
    private func registerHotkeys() {
        let commandOption = cmdKey | optionKey

        HotkeyManager.shared.register(keyCode: kVK_ANSI_H, modifiers: commandOption) {
            StickerManager.shared.toggleHidden()
        }
        HotkeyManager.shared.register(keyCode: kVK_ANSI_L, modifiers: commandOption) {
            StickerManager.shared.toggleLocked()
        }
        HotkeyManager.shared.register(keyCode: kVK_Delete, modifiers: commandOption) {
            StickerManager.shared.removeSelected()
        }
        HotkeyManager.shared.register(keyCode: kVK_ANSI_D, modifiers: commandOption) {
            StickerDockController.shared.toggle()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "\(Brand.displayName) 종료",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        NSApp.mainMenu = mainMenu
    }

    // 메뉴바 앱이므로 마지막 윈도우가 닫혀도 종료하지 않는다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Finder에서 PNG를 앱 아이콘에 떨구면 바로 화면에 띄운다.
    func application(_ application: NSApplication, open urls: [URL]) {
        StickerManager.shared.addAll(urls: urls.filter { StickerLibrary.isSupported($0) })
    }
}
