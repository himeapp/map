# 인수인계 — UI 기획서(HTML) → SwiftUI 앱 이식

이 문서는 `ux_*.html` 기획서를 실제 `himemap` SwiftUI 앱에 옮기는 작업의 진행 상황과 다음 할 일을 정리한다. 다른 기기에서 이어서 진행할 때 이 문서부터 읽으면 된다.

## 결정된 방향

- **실제 MapKit 지도는 유지**하고, 그 위의 카드·바텀시트·리스트·다이나믹 아일랜드만 HTML 기획서 디자인으로 입힌다. (가짜 지도 재현 ❌)
- HTML 파일들(`ux_stage0`, `ux_stage2`, `ux_stage3`, `ux_stage3_sub`, `ux_stage_walk`, `ux_transfer`, `ux_arrive`, `ux_reroute`, `ux_stage1_navmap`)이 **화면별 디자인 스펙**이다.
- 색/컴포넌트 토큰은 `Theme.swift`에 모아 둠. HTML `:root` 변수와 1:1 (appBlue/appGreen/appOrange/appPurple/appRed/appLine 등).

## 다른 기기에서 시작하기

```bash
git clone https://github.com/himeapp/map.git && cd map
# 1) API 키 파일 생성 (gitignore라 저장소에 없음 — 필수)
cat > Secrets.xcconfig <<'EOF'
KAKAO_API_KEY = 카카오_REST_API_키
ODSAY_API_KEY = ODsay_키
DATA_GO_KR_KEY = 공공데이터포털_일반인증키
SEOUL_OPEN_API_KEY = 서울_열린데이터광장_키
EOF
# 2) 프로젝트 생성 + 빌드 (xcodeproj는 gitignore → 매번 생성)
xcodegen generate
xcodebuild -project himemap.xcodeproj -scheme himemap \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
키 없이도 **컴파일은 됨**(UI 작업엔 충분). 실제 경로/도착 데이터는 키 있어야 채워짐.

## 완료 (빌드·시뮬레이터 실행 검증됨)

- `Theme.swift` — 신규. 색 토큰, `Color(hex:)`, `Vehicle.displayColor`(등급별 번호색), `ArrivalTier`(곧/중간/늦음), `DynamicIslandPill`, `ETABadge`.
- **즐겨찾기 칩 출발/도착 동작** — `TransitViewModel.useSavedPlace(_:)` 추가. 활성 입력 필드(`searchTarget`)를 따라 출발/도착에 채움. 홈 칩 + 검색 시트 안 칩 모두 연결(`HomeView.swift`).
- **정류소 실시간**(`WaitingView.swift`) → `ux_stage2`: 도착 바, 정류장 그룹 헤더, HTML식 버스 행(등급색 tabular 번호 + 방향/경유 + ETA 배지), 첫 그룹 "고른 길"·"추천" 강조, **"탔어요" 2탭 탑승**(1탭=확인칩, 2탭=`boardVehicle`).
- **탑승 후**(`OnboardView.swift`) → `ux_stage3`: 버스 배지, "○○에서 내려요", 세로 타임라인(afterSteps), 하차 박스, **긴급 카드(확장형)** — 정거장 지나침/반대방향/목적지 변경.

## 다음 할 일 (우선순위 순)

기존 `appState`(`TransitViewModel.swift`)는 `home / searching / waiting / onboard / intercity`. 아래 화면들은 **새 상태 추가 + 트리거 연결**이 필요하다. `ContentView.swift`의 `switch vm.appState`에 케이스 추가하는 구조.

1. **도착 완료** (`ux_arrive.html`) — 신규 `ArriveView`.
   - 트리거(택1): 탑승 후 목적지 좌표 근접 감지 / 사용자가 "내렸어요" 탭 / 마지막 afterStep(arrive) 도달.
   - 내용: 초록 체크 히어로, 여정 요약(총 소요·출발/도착 시각·수단·도보), 미니 타임라인, "새 목적지 검색"→`goHome()`+`startSearch`.
   - VM: `appState`에 `.arrived` 추가 + `arrive()` 메서드.

2. **경로 이탈** (`ux_reroute.html`) — 신규 `RerouteView` 또는 오버레이.
   - 트리거: 위치 추적(`livePositions`/사용자 위치) 경로 이탈 감지. 지금은 `OnboardView` 긴급카드 "정거장 지나침"이 `exitOnboard`+`fetchRoutes`로 임시 처리 중 → 이걸 reroute 화면으로 교체.
   - 내용: 빨간 경고 배너, 출발=현위치(고정)/도착=그대로, "지금 위치에서 다시 탐색"→`fetchRoutes()`.

3. **도보 안내** (`ux_stage_walk.html`) — 경로 선택 → 정류소 탑승 **사이** 상태.
   - 트리거: 정류소까지 도보 구간이 있을 때 `waiting` 진입 전 거침. (단순화하려면 스킵 가능 — 결정 필요)
   - 내용: 지도 + 하단 모달(방향 "직진 후 좌회전", 진행바, 남은 거리, 목표 정류소 행 740·3분 후). 다이나믹 아일랜드 회색 점 "○○ 정류소로 도보".
   - VM: `.walkingToStop` 추가 + 진행 시뮬/위치 기반 진행.

4. **지하철 트래킹** (`ux_stage3_sub.html`) — 탑승 수단이 지하철일 때 `OnboardView` 분기.
   - 내용: 가로 노선도(지나온 역 회색/현재역 초록 펄스/하차역 강조)가 왼쪽으로 흐름. 호선 색은 `Vehicle.lineColor`(이미 모델에 있음) 사용.
   - 구현: `OnboardView`에서 `selectedOption.vehicle.type == .subway`면 노선도형 타임라인, 아니면 현재 세로 타임라인.

5. **환승** (`ux_transfer.html`) — 멀티 leg 경로에서 하차 후 다음 정류소까지 도보.
   - 트리거: afterSteps에 transfer/board 후속 구간이 있을 때.
   - 내용: 회색 점선 도보 경로, "○○번 하차 완료" 초록 배너, 도보 타임라인(하차→걷는 중→도착 정류소).

6. **검색 화면**(`ux_stage0.html`) 정교화 — 현재 네이티브 `.sheet` 유지. 기획서의 하단 출발/도착 바 + 키보드 밀어올림까지 맞출지는 선택(네이티브 시트가 더 iOS다움). `ux_keyboard_cases.html` 참고.

## 참고 / 주의

- **`xcodeproj`·`Generated/`는 gitignore** → `xcodegen generate` 매번 필요. `project.yml`이 소스 오브 트루스.
- **`TransitModels.swift`/`ODsayService.swift`**의 일부 변경은 기존 작업(내 작업 아님). 보존됨.
- 모델에 이미 있는 자산: `Vehicle.lineColor`(호선/버스등급 hex), `DepartureGroup`/`BoardableOption`(정류장 그룹·실시간 도착), `BusPosition`(지도 핀), `RouteStep`/`StepType`(타임라인).
- 미사용으로 비워둔 화면 진입점은 없음. 새 화면은 `appState` 케이스부터 추가.
- `app.html`은 1차 클릭형 목업(참고용). 정본 스펙은 `ux_*.html`.
```
```
