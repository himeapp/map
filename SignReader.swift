import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - 간판 읽기 (음성 인식)
//
// 사용자가 정면에 보이는 간판을 소리내어 읽으면 ko-KR 음성을 텍스트로 변환한다.
// 변환된 텍스트는 OrientationService 가 카카오 로컬에서 좌표로 바꿔 "내가 보는 방향"을 계산.
// 길치/방향치가 출구에서 헤맬 때, 나침반(부정확) 대신 눈앞 간판으로 방향을 잡게 해준다.

@MainActor
final class SignReader: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var permissionDenied: Bool = false
    @Published var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 마이크 + 음성인식 권한 요청. 둘 다 허용돼야 true.
    func requestPermission() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK: Bool = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        let ok = speechOK && micOK
        permissionDenied = !ok
        return ok
    }

    /// 녹음 시작. 부분 인식 결과를 transcript 로 실시간 publish.
    func start() {
        transcript = ""
        errorText = nil
        task?.cancel()
        task = nil

        guard let recognizer, recognizer.isAvailable else {
            errorText = "지금은 음성 인식을 쓸 수 없어요. 키보드로 입력해 주세요."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "마이크를 켤 수 없어요. 키보드로 입력해 주세요."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorText = "마이크를 시작할 수 없어요. 키보드로 입력해 주세요."
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.finish() }
            }
        }
    }

    /// 녹음 종료 (사용자가 "다 읽었어요" 누를 때).
    func stop() {
        finish()
    }

    private func finish() {
        guard isRecording else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
