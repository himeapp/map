import SwiftUI
import CoreLocation

// MARK: - 방향 잡기 시트 (간판 읽기 → 내가 가야 할 방향)
//
// "정면에 보이는 간판 하나를 읽으세요" → 음성 인식 → 카카오 로컬에서 좌표 → 방향 계산.
// 길치/방향치가 출구를 나와 어디로 걸어야 할지 한 번에 잡게 해준다.
// 간판으로 구한 '진짜 정면'으로 나침반을 보정해, 몸을 돌리면 화살표가 실시간으로 따라온다.

struct OrientationView: View {
    let target: Coordinate
    let targetName: String
    var onClose: () -> Void

    @StateObject private var reader = SignReader()
    @ObservedObject private var location = LocationManager.shared

    @State private var phase: Phase = .intro
    @State private var candidates: [SignCandidate] = []
    @State private var confirmSign: String = ""
    @State private var confirmInstruction: String = ""
    @State private var confirmDetail: String = ""
    @State private var manualText: String = ""
    @State private var showManual = false
    @State private var message: String?
    @State private var pulse = false

    enum Phase { case intro, listening, resolving, pick, confirm, error }

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemBackground))
    }

    private var handle: some View {
        Capsule().fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .padding(.top, 10).padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:                introView
        case .listening:            listeningView
        case .resolving:            resolvingView
        case .pick:                 pickView
        case .confirm:              confirmView
        case .error:                errorView
        }
    }

    // MARK: - ① 안내

    private var introView: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("어느 쪽으로 가요?")
                    .font(.system(size: 22, weight: .heavy))
                Text("정면에 보이는 간판 하나를\n소리내어 읽어주세요")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 4)

            micButton(title: "간판 읽기 시작", systemImage: "mic.fill", action: beginListening)

            if showManual {
                manualField
            } else {
                Button("말하기 어려우면 키보드로 입력") { showManual = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appBlue)
            }
        }
    }

    // MARK: - ② 듣는 중

    private var listeningView: some View {
        VStack(spacing: 24) {
            Text("듣고 있어요")
                .font(.system(size: 20, weight: .heavy))

            ZStack {
                Circle().fill(Color.appBlue.opacity(0.12)).frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.08 : 0.82)
                    .opacity(pulse ? 0.5 : 1)
                Circle().fill(Color.appBlue.opacity(0.18)).frame(width: 84, height: 84)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.appBlue)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            Text(reader.transcript.isEmpty ? "간판 이름을 읽어주세요…" : "“\(reader.transcript)”")
                .font(.system(size: 17, weight: reader.transcript.isEmpty ? .regular : .bold))
                .foregroundColor(reader.transcript.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 26)

            Button(action: finishListening) {
                Text("다 읽었어요")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - ③ 찾는 중

    private var resolvingView: some View {
        VStack(spacing: 18) {
            ProgressView().scaleEffect(1.3)
            Text("“\(searchText)” 위치를 찾는 중…")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(height: 180)
    }

    // MARK: - ④ 후보 고르기 (같은 이름이 여러 곳일 때)

    private var pickView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("어떤 간판인가요?")
                .font(.system(size: 20, weight: .heavy))
            Text("정면에서 읽은 간판을 골라주세요")
                .font(.system(size: 14)).foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(candidates.prefix(5)) { c in
                    Button { choose(c) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name).font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(c.address).font(.system(size: 12)).foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text("\(Int(c.distance))m")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appBlue)
                        }
                        .padding(14)
                        .background(Color.appBg, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            retryRow
        }
    }

    // MARK: - ⑤ 확인 (지도를 맞췄어요)

    private var confirmView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.appGreen.opacity(0.15)).frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.appGreen)
            }
            .padding(.top, 8)

            Text("지도를 맞췄어요")
                .font(.system(size: 22, weight: .heavy))

            Text(confirmInstruction)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.appBlue)

            Text(confirmDetail)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("‘\(confirmSign)’ 기준 · 화면 위쪽이 지금 보는 방향이에요")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onClose) {
                Text("지도 보기")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button("다시 잡기") { resetToIntro() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appBlue)
        }
    }

    // MARK: - ⑥ 오류

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 38)).foregroundColor(.appOrange)
            Text(message ?? "간판을 못 찾았어요")
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
            Text("간판 이름을 다시 읽거나, 더 크게 적힌 다른 간판을 읽어보세요")
                .font(.system(size: 14)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            manualField
            retryRow
        }
    }

    // MARK: - 공통 조각

    private func micButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.appBlue).frame(width: 96, height: 96)
                    Image(systemName: systemImage)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.appBlue)
            }
        }
        .buttonStyle(.plain)
    }

    private var manualField: some View {
        HStack(spacing: 8) {
            TextField("간판 이름 입력", text: $manualText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.appBg, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.search)
                .onSubmit { resolveManual() }
            Button(action: resolveManual) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(manualText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .appBlue)
            }
            .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var retryRow: some View {
        Button { resetToIntro() } label: {
            Label("다시 읽기", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.appBlue)
        }
        .padding(.top, 4)
    }

    // MARK: - 상태 계산

    private var searchText: String {
        manualText.isEmpty ? reader.transcript : manualText
    }

    // MARK: - 동작

    private func beginListening() {
        Task {
            let ok = await reader.requestPermission()
            guard ok else {
                message = "마이크 권한이 꺼져 있어요. 설정에서 켜거나 키보드로 입력해 주세요."
                showManual = true
                phase = .error
                return
            }
            manualText = ""
            reader.start()
            if reader.errorText != nil {
                message = reader.errorText
                showManual = true
                phase = .error
            } else {
                phase = .listening
            }
        }
    }

    private func finishListening() {
        reader.stop()
        let text = reader.transcript
        Task { await resolve(text: text) }
    }

    private func resolveManual() {
        let text = manualText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task { await resolve(text: text) }
    }

    private func resolve(text: String) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            message = "간판 이름을 못 들었어요. 다시 시도해 주세요."
            phase = .error
            return
        }
        guard let cur = location.current else {
            message = "현재 위치를 아직 못 잡았어요. 잠시 후 다시 시도해 주세요."
            phase = .error
            return
        }
        phase = .resolving
        let user = Coordinate(lat: cur.latitude, lng: cur.longitude)
        let found = await OrientationService.candidates(for: cleaned, near: user)
        candidates = found

        if found.isEmpty {
            message = "‘\(cleaned)’ 간판을 주변에서 못 찾았어요"
            showManual = true
            phase = .error
        } else if found.count == 1 || found[0].distance * 1.6 < found[1].distance {
            // 후보가 하나이거나 가장 가까운 게 확실히 가까우면 바로 결정
            choose(found[0])
        } else {
            phase = .pick
        }
    }

    private func choose(_ candidate: SignCandidate) {
        guard let cur = location.current else { return }
        let user = Coordinate(lat: cur.latitude, lng: cur.longitude)
        let r = OrientationService.result(user: user, sign: candidate, target: target)
        confirmSign = candidate.name
        confirmInstruction = "\(targetName): \(r.instruction)"
        confirmDetail = r.detail
        // 핵심: 간판 방위각(= 내가 보는 방향)이 화면 위쪽이 되도록 지도를 한 번 회전.
        MapController.shared.orient(toHeading: r.userHeading, center: user)
        phase = .confirm
    }

    private func resetToIntro() {
        reader.stop()
        candidates = []
        manualText = ""
        message = nil
        phase = .intro
    }
}
