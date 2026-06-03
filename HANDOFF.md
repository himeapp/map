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
- **정류소 실시간**(`WaitingView.swift`) → `ux_stage2`: 도착 바, 정류장 그룹 헤더, HTML식 버스 행(등급색 tabular 번호 + 방향/경유 + ETA 배지), 첫 그룹 "고른 길"·"추천" 강조, **"탔어요" 2탭 탑승**(1탭=확인칩, 2탭=`boardVehicle`). 정류장 헤더 **"도보 N분" 배지 탭 → 도보 안내**(`.walkingToStop`) 진입.
- **탑승 후**(`OnboardView.swift`) → `ux_stage3`: 버스 배지, "○○에서 내려요", 세로 타임라인(afterSteps), 하차 박스, **긴급 카드(확장형)** — 정거장 지나침(→`startReroute`)/반대방향/목적지 변경. **지하철이면 `SubwayRouteMap`(가로 노선도)로 분기**. 환승 구간 있으면 "환승하러 내렸어요" 버튼(→`startTransfer`), 없으면 "도착했어요"(→`arrive`).
- **도착 완료**(`ArriveView.swift`) → `ux_arrive`: 초록 체크 히어로, 여정 요약(총소요·출발/도착 시각·수단·도보), 미니 가로 타임라인, "새 목적지 검색"/"즐겨찾기 추가". VM `.arrived` + `arrive()`, `boardedAt`/`arrivedAt` 기록.
- **경로 이탈**(`RerouteView.swift`) → `ux_reroute`: 빨간 경고 배너, OD카드(출발=현위치/도착=그대로), "다시 탐색"→`confirmReroute`(=`fetchRoutes`). VM `.rerouting` + `startReroute/confirmReroute/cancelReroute`.
- **도보 안내**(`WalkToStopView.swift`) → `ux_stage_walk`: 방향 헤더, 진행바, 목표 정류소 + 버스 ETA, "정류소 도착"→`arriveAtStop`. VM `.walkingToStop` + `walkingGroup`.
- **환승**(`TransferView.swift`) → `ux_transfer`: "○○번 하차 완료" 배너, 회색 점선 도보 타임라인(하차→걷는 중→도착 정류소), "정류소 도착"→`arriveAtTransferStop`. VM `.transferWalking`.

## 다음 할 일

1. **검색 화면**(`ux_stage0.html`) 정교화 — 현재 네이티브 `.sheet` 유지. 기획서의 하단 출발/도착 바 + 키보드 밀어올림까지 맞출지는 선택(네이티브 시트가 더 iOS다움). `ux_keyboard_cases.html` 참고. **(미착수 — 우선순위 낮음/선택)**

2. **트리거 실측화(시뮬 → 실제)** — 현재 화면 전환은 대부분 *사용자 선언/수동 탭* 기반(도착·환승·도보 도착·이탈). 위치 서비스(CLLocationManager) 연동해서:
   - 도착 감지: 목적지 좌표 근접 시 `arrive()` 자동 제안.
   - 도보/환승 진행: 실제 거리 기반 진행바·남은 거리.
   - 이탈 감지: 경로 폴리라인 이탈 시 `startReroute()` 자동.
   - 단, 핵심 컨셉상 **탑승/하차는 유저 선언 유지**(앱이 멋대로 "탔다" 판단 금지).

3. **지하철 노선도 실데이터** — 현재 `SubwayRouteMap`은 정거장 *수*만으로 점을 그림(역명은 출발/하차만). 경유 역명 리스트를 ODsay 경로 응답에서 뽑아 채우면 실제 노선도가 됨.

## 참고 / 주의

- **`xcodeproj`·`Generated/`는 gitignore** → `xcodegen generate` 매번 필요. `project.yml`이 소스 오브 트루스.
- **`TransitModels.swift`/`ODsayService.swift`**의 일부 변경은 기존 작업(내 작업 아님). 보존됨.
- 모델에 이미 있는 자산: `Vehicle.lineColor`(호선/버스등급 hex), `DepartureGroup`/`BoardableOption`(정류장 그룹·실시간 도착), `BusPosition`(지도 핀), `RouteStep`/`StepType`(타임라인).
- 미사용으로 비워둔 화면 진입점은 없음. 새 화면은 `appState` 케이스부터 추가.
- `app.html`은 1차 클릭형 목업(참고용). 정본 스펙은 `ux_*.html`.
```
```
