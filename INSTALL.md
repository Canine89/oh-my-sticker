# 설치

## Homebrew로 설치 (권장)

```bash
brew install --cask canine89/tap/oh-my-sticker
```

탭을 먼저 추가해도 됩니다.

```bash
brew tap canine89/tap
brew install --cask oh-my-sticker
```

## 직접 내려받아 설치

1. [Releases](https://github.com/Canine89/oh-my-sticker/releases)에서 최신 `oh-my-sticker-<버전>.dmg`를 내려받습니다.
2. 받은 DMG를 엽니다.
3. `oh-my-sticker` 앱을 `Applications` 폴더로 끌어다 놓습니다.
4. 앱을 실행합니다.

Apple 공증(notarization)을 받은 앱이라 "확인되지 않은 개발자" 경고 없이 바로 열립니다.

## 처음 켜면

Dock에는 아이콘이 뜨지 않습니다. **메뉴 막대의 도장 아이콘**과 화면 아래쪽 **스티커 독**으로 씁니다.

독에 PNG를 끌어다 놓으면 보관함에 담기고, 독 아이콘을 화면으로 끌어내면 그 자리에 스티커가 놓입니다. 자세한 사용법은 메뉴 → **사용법**, 또는 [README](README.md).

권한 요청은 없습니다. 화면 녹화·접근성 권한 모두 필요하지 않습니다.

## 업데이트

앱이 하루 한 번 새 버전을 확인합니다. 메뉴 → **업데이트 확인…** 으로 즉시 확인할 수도 있습니다.

## 지우기

Homebrew로 설치했다면:

```bash
brew uninstall --cask oh-my-sticker      # 앱만 제거
brew uninstall --zap --cask oh-my-sticker # 설정·보관함까지 제거
```

직접 설치했다면 앱을 휴지통에 넣고, 남는 파일을 지우려면:

```bash
rm -rf ~/Library/Application\ Support/oh-my-sticker
rm -f ~/Library/Preferences/com.goldenrabbit.ohmysticker.plist
```

보관함에 담아 둔 스티커 이미지도 `Application Support` 폴더 안에 있으니, 남기고 싶으면 먼저 옮겨두세요.

## 요구 사항

macOS 14(Sonoma) 이상.
