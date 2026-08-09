import AppKit

// 메뉴바 상주(accessory) 앱. 스토리보드 없이 코드로 부트스트랩한다.
let app = NSApplication.shared
// top-level 코드는 nonisolated 취급이지만 실제로는 메인 스레드다.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
