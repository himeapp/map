# himemap — 대중교통 앱

전국 도시 내 / 도시 간 이동을 한 앱으로. 화면 전환과 애니메이션 최소화.

## 프로젝트 구조

```
himemap/
├── Models/
│   └── TransitModels.swift           # Place, BoardableOption, IntercityOption, BusPosition 등
├── Services/
│   ├── KakaoTransitService.swift     # 카카오 로컬 (장소 검색)
│   ├── ODsayService.swift            # 대중교통 경로 (도시 내)
│   ├── RealtimeBusService.swift      # TAGO 실시간 버스 도착
│   ├── BusPositionService.swift      # TAGO 실시간 버스 위치
│   ├── IntercityBusService.swift     # TAGO 시외/고속버스 시간표
│   ├── TrainService.swift            # TAGO 열차 시간표
│   ├── SubwayInfoService.swift       # TAGO 지하철 정적정보
│   └── PersistenceService.swift      # UserDefaults
├── ViewModels/
│   └── TransitViewModel.swift        # 메인 상태 관리
├── Views/
│   ├── HomeView.swift                # 지도 + 검색 + 버스위치 핀
│   ├── WaitingView.swift             # 시내 버스 대기
│   ├── OnboardView.swift             # 탑승 후 이후 경로
│   └── IntercityView.swift           # 시외/고속/열차 시간표
└── ContentView.swift                 # 루트 + 상태별 라우팅
```

## Info.plist 키

```xml
<!-- 카카오 로컬 (장소 검색) -->
<key>KAKAO_API_KEY</key>
<string>여기에_카카오_REST_API_키</string>

<!-- ODsay (도시 내 대중교통 경로) -->
<key>ODSAY_API_KEY</key>
<string>여기에_ODsay_API_키</string>

<!-- 공공데이터포털 TAGO (실시간 버스 + 시외/고속/열차/지하철) -->
<!-- 일반 인증키(Decoding) — 모든 TAGO API에 공통 -->
<key>DATA_GO_KR_KEY</key>
<string>여기에_공공데이터포털_일반인증키</string>

<!-- 서울 열린데이터광장 (실시간 지하철 도착 — 수도권) — 신규 추가 예정 -->
<key>SEOUL_OPEN_API_KEY</key>
<string>여기에_서울_열린데이터광장_인증키</string>

<!-- 위치 권한 -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>현재 위치를 출발지로 사용하기 위해 필요합니다</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>경로 안내 중 위치 추적에 사용됩니다</string>
```

## API 발급

| 키 | 사이트 | 비고 |
|---|---|---|
| `KAKAO_API_KEY` | https://developers.kakao.com | REST API 키. 일 300k |
| `ODSAY_API_KEY` | https://lab.odsay.com | 일 5k |
| `DATA_GO_KR_KEY` | https://data.go.kr | 일반 인증키(Decoding) 하나로 아래 7개 API 활용신청 |
| `SEOUL_OPEN_API_KEY` | https://data.seoul.go.kr | "실시간 지하철 도착정보" 데이터셋 (수도권 전체 커버) |

### data.go.kr 활용신청 (TAGO 7종)

| API | 우리가 쓰는 곳 |
|---|---|
| 국토교통부_(TAGO)_버스도착정보 | 정류장 도착 분 |
| 국토교통부_(TAGO)_버스정류소정보 | 좌표→nodeId 매핑 |
| 국토교통부_(TAGO)_버스위치정보 | 지도 위 실시간 버스 핀 |
| 국토교통부_(TAGO)_시외버스정보 | 시외버스 시간표 |
| 국토교통부_(TAGO)_고속버스정보 | 고속버스 시간표 |
| 국토교통부_(TAGO)_열차정보 | KTX/새마을/무궁화 시간표 |
| 국토교통부_(TAGO)_지하철정보 | 지하철 역사/노선 정적정보 |

모두 같은 인증키 하나로 동작. 각각 활용신청만 별도로 누르면 됨 (보통 자동승인).

## 동작 흐름

### 도시 내 (서울 내 이동 등)
1. 검색 → 출발/도착 선택
2. ODsay로 경로 조회 → `BoardableOption` 리스트
3. TAGO 실시간 도착으로 버스 옵션 도착 분 채움
4. 탑승 누르면 TAGO 버스위치 폴링 → 지도에 핀

### 도시 간 (서울→부산 등)
1. 출발/도착 좌표 거리 80km 초과 OR ODsay 결과 없음 → 자동으로 인터시티 모드
2. IntercityView 표시 (탭: 시외 / 고속 / 열차)
3. 출발 도시 → 도착 도시 선택 → 시간표 표시

## 핵심 UX 원칙 (코드에 반영)

1. **경로 유지** — `PersistenceService.saveLastRoute()` 앱 종료 후 자동 복원
2. **경로별 분리 없음** — `BoardableOption` flat 리스트
3. **화면 전환 최소화** — `appState`로 같은 지도 위 바텀시트만 변경
4. **즉각 전환** — `animation(nil)` 애니메이션 차단
5. **모드 자동 판정** — 거리/결과 기반으로 시내/인터시티 자동 분기

## 다음 단계

- [x] 대중교통 경로 API 파싱 (ODsay)
- [x] 실시간 버스 도착 (TAGO)
- [x] 실시간 버스 위치 (TAGO)
- [x] 시외/고속/열차 시간표 (TAGO)
- [x] 지하철 정적정보 (TAGO)
- [x] 거리 기반 시내/인터시티 자동 모드 전환
- [ ] **서울 열린데이터광장 실시간 지하철 도착** (`SEOUL_OPEN_API_KEY` 발급 후)
- [ ] 인터시티 모드 진입 시 from/to → cityCode 자동 매핑 (지금은 사용자가 picker로 재선택)
- [ ] 시외버스 터미널 단위 picker (현재 도시 → 첫 터미널만 사용)
- [ ] 열차 도시→역 매핑 정확도 (현재 도시의 첫 역만 사용)
- [ ] ODsay → TAGO 정류장 매핑 정확도 (동음이의 정류장 위험)
- [ ] MapKit 경로선 표시
- [ ] Live Activity (잠금화면 정거장 카운트다운)
- [ ] 위치 기반 자동 출발지 설정
- [ ] 부산/대구/광주 등 광역시 지하철 실시간 (해당 지역 API 별도 — 데이터 부실)
