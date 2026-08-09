import AppKit

/// 앱 이름·식별 문자열을 한곳에 모은다. 이름을 바꿀 땐 여기만 고치면 UI 문자열이 따라온다.
enum Brand {
    static let name = "oh-my-sticker"
    static let displayName = "oh-my-sticker"
    /// Application Support 하위 폴더 이름
    static let supportFolder = "oh-my-sticker"
    /// 메뉴 막대 아이콘 (SF Symbols)
    static let menuBarSymbol = "seal"
}
