# oh-my-sticker

강의·발표 화면 위에 PNG 스티커를 띄워 두고, 마우스로 옮기고 크기를 바꾸고 앞뒤 순서를 조정하는 macOS 메뉴 막대 앱.

- 스티커 한 장 = 투명 배경의 떠 있는 패널 윈도우 한 개
- 키노트/파워포인트 **전체 화면 발표 위에도** 보인다 (`popUpMenu` 윈도우 레벨 + `canJoinAllSpaces`)
- 스티커를 클릭해도 **발표 중인 앱의 포커스를 빼앗지 않는다** (`nonactivatingPanel`)
- 화면 녹화·접근성 권한이 필요 없다

## 스티커 독

macOS Tahoe의 Dock을 닮은 반투명 팔레트가 화면에 떠 있다. 배경 재질과 창 그림자를 둥근 마스크 이미지로 오려내 모서리에 사각형 잔상이 남지 않게 했다. 빈 곳을 끌면 독 자체를 옮길 수 있고, `⌥⌘D`로 감췄다 부른다.

| 하고 싶은 것 | 방법 |
|---|---|
| 스티커를 원하는 자리에 올리기 | 독 아이콘을 **화면으로 끌어낸다**. 놓은 자리에 스티커가 생긴다 |
| 올리기/내리기 토글 | 독 아이콘을 그냥 클릭. 올라와 있는 아이콘 아래엔 Dock처럼 **점**이 찍힌다 |
| 화면에서 내리기 | 스티커를 **독 위로 끌어다 놓는다**. 보관함에는 그대로 남는다 |
| 보관함에 담기 | 이미지 파일을 **독에 떨어뜨린다**. 보관 폴더로 복사되어 계속 재활용된다 |
| 아이콘 크기·보관 폴더·삭제 | 독에서 오른쪽 클릭 |

보관 폴더는 기본이 `~/Library/Application Support/oh-my-sticker/Stickers/` 이고, 독 우클릭 → "보관함 폴더 바꾸기…"로 원하는 폴더를 쓸 수 있다. Finder로 그 폴더에 직접 넣은 이미지도 폴더 감시로 바로 독에 나타난다. 화면 밖에서 온 스티커(Finder에서 연 PNG 등)를 독에 떨궈 내리면 그때 보관함에 자동으로 담긴다.

## 그 밖의 조작

메뉴 막대의 도장 아이콘을 누른다.

| 하고 싶은 것 | 방법 |
|---|---|
| 스티커 띄우기 | 독에서 고르거나, **스티커 파일 열기…** / Finder에서 PNG를 "다음으로 열기" |
| 옮기기 | 스티커를 그냥 끈다 |
| 크기 조정 | 한 번 클릭해 선택 → 네 모서리 핸들을 끈다 (비율 유지). `⌥`를 누른 채 끌면 비율 무시 |
| 모양 늘리기 | **같은 핸들**을 `⇧`를 누른 채 끌면 그 모서리만 잡아당겨져 모양이 늘어난다 (그림 크기의 90%까지) |
| 앞뒤 순서 | 스티커에서 오른쪽 클릭 → 맨 앞으로 / 한 칸 앞으로 / 한 칸 뒤로 / 맨 뒤로 |
| 투명도·좌우 반전·복제·모양 원래대로 | 오른쪽 클릭 메뉴 |
| 지우기 | 오른쪽 클릭 → 이 스티커 지우기, 또는 `⌥⌘⌫` |
| 잠깐 감췄다 다시 부르기 | `⌥⌘H` |
| 독 보이기/숨기기 | `⌥⌘D` |
| 스티커를 둔 채 아래 앱 클릭 | `⌥⌘L` (클릭 통과 잠금) |

**배치 기억**: 앱을 껐다 켜면 마지막 배치(위치·크기·투명도·반전·앞뒤 순서)를 그대로 되살린다. 메뉴에서 끌 수 있다.

전역 단축키는 Carbon `RegisterEventHotKey` 기반이라 다른 앱을 쓰는 중에도 듣는다.

## 설치

[Releases](https://github.com/Canine89/oh-my-sticker/releases)에서 최신 DMG를 받아 앱을 `Applications`로 끌어다 놓는다. Apple 공증을 받았으므로 Gatekeeper 경고 없이 바로 열린다. 자세한 내용은 [INSTALL.md](INSTALL.md).

앱은 하루 한 번 새 버전을 확인하고, 메뉴에서 **업데이트 확인…** 으로 즉시 확인할 수도 있다.

## 빌드

```bash
brew install xcodegen          # 최초 1회
xcodegen generate              # project.yml → .xcodeproj 재생성
open oh-my-sticker.xcodeproj # Xcode에서 Run
```

명령줄 빌드:

```bash
xcodebuild -project oh-my-sticker.xcodeproj -scheme oh-my-sticker \
  -configuration Release -derivedDataPath build/dd build
```

> `.xcodeproj`와 `Config/Info.plist`는 **생성물**이다. 직접 고치지 말고 `project.yml`을 고친 뒤 `xcodegen generate`.

## 구조

```
Sources/
  App/      main.swift · AppDelegate · MenuBarController · Brand
  Sticker/  StickerManager(전체 목록·z 순서·저장) · StickerController(스티커 1장) ·
            StickerWindow(투명 패널) · StickerView(그리기·이동·리사이즈·워프) ·
            ImageContentBox(투명 여백을 뺀 그림 영역 계산)
  Dock/     StickerDockController(독 패널·위치·폴더 감시) · StickerDockView(아이콘·끌어내기·드롭) ·
            FolderWatcher
  Library/  보관함 저장/복사/삭제 + ImageIO 썸네일
  Hotkey/   Carbon 전역 단축키
  Settings/ UserDefaults 설정 + 세션 JSON 저장/복원
```

- `StickerManager.stickers` 배열의 순서가 곧 z 순서(0 = 맨 뒤). 조작할 때마다 그 순서대로 `orderFront`를 다시 걸어 쌓임을 강제한다.
- 세션은 `~/Library/Application Support/oh-my-sticker/session.json`.
- 독 아이콘을 끌어낼 때는 `NSDraggingSession`을 쓰지 않는다. 드래그가 시작되는 순간 스티커 윈도우를 만들고 커서를 따라오게 해서, 손을 떼는 자리에 정확히 놓이도록 했다.
- 독은 스티커보다 한 단계 위 윈도우 레벨이라 항상 손에 닿는다. 목록·선택 변화는 `StickerManager.didChangeNotification`으로 메뉴바와 독에 함께 전달된다.

### 핸들과 모양 워프

- 핸들은 네 모서리 하나뿐이다. 그냥 끌면 크기 조정, `⇧`를 누른 채 끌면 그 모서리만 잡아당기는 워프. Shift를 누르면 핸들이 채워져 지금 어느 쪽으로 동작하는지 보인다.
- 핸들 자리는 이미지 사각형이 아니라 **투명한 여백을 뺀 실제 그림의 모서리**다. `ImageContentBox`가 알파를 128px로 줄여 훑고 내용이 있는 영역만 남긴다.
- 크기 조정은 그 그림 영역을 기준으로 배율을 구하고, 반대편 모서리를 화면에 못 박은 채 창 전체에 같은 배율을 먹인다.
- 모서리는 그림 크기의 90%까지 끌 수 있다. 그만큼 창을 넓혀야 잘리지 않으므로(그림의 약 3배), 워프 중에는 늘어난 사각형 안에서만 마우스를 받도록 `hitTest`를 좁혀 빈 여백이 뒤쪽 스티커의 클릭을 가로채지 않게 한다.
- 워프 렌더는 네 모서리 + 무게중심으로 만든 부채꼴 삼각형마다 아핀 변환을 걸어 그린다. 이웃 삼각형끼리 1px 남짓 겹치게 해 경계의 실틈을 없앴다.
- 늘어난 그림이 잘리지 않도록, 워프를 시작하는 순간 창 여백을 창 짧은 변의 22%로 넓히고 그림의 화면 위치는 그대로 둔다. 이 여백은 창 크기에 비례하므로 이후 크기를 조정해도 비율이 어긋나지 않는다.
- 좌우 반전은 그림 영역과 모서리별 변위까지 함께 뒤집어, 핸들이 그림과 어긋나지 않게 한다.

## 배포

`scripts/release.sh`가 Developer ID 서명 → Apple 공증 → DMG/ZIP 패키징 → EdDSA 서명된 appcast → GitHub Release까지 한 번에 처리한다.

```bash
./scripts/release.sh                    # 로컬 테스트용 DMG만
./scripts/release.sh 1.0.1              # 버전 올려 DMG+ZIP+appcast 생성 (게시 X)
./scripts/release.sh 1.0.1 --publish    # 위 + 커밋/푸시 + GitHub Release 업로드
```

릴리스 전에 `CHANGELOG.md`에 `## <새버전>` 섹션을 먼저 추가한다. 그 내용이 Sparkle 업데이트 창과 GitHub 릴리스 노트에 그대로 나간다. 빌드 번호(`CURRENT_PROJECT_VERSION`)는 스크립트가 매번 올린다 — 이게 올라가야 Sparkle이 업데이트를 감지한다.

서명 신원은 고정된 Developer ID(Team `M7NU9F8CZN`)를 쓴다. ad-hoc으로 서명하면 빌드마다 앱이 "다른 앱"으로 취급되어 업데이트마다 사용자 설정과 권한이 풀린다.
