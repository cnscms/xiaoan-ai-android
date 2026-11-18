import AVFoundation
import Foundation

final class XiaoZhiAudioManager {
    enum AudioError: LocalizedError {
        case microphonePermissionDenied
        case invalidInputFormat
        case codec(String)
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "麦克风权限未授予"
            case .invalidInputFormat:
                return "无法读取麦克风音频格式"
            case let .codec(message):
                return message
            case let .engine(message):
                return "音频引擎错误：\(message)"
            }
        }
    }

    typealias PacketHandler = (Data) -> Void
    typealias ErrorHandler = (Error) -> Void

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let audioQueue = DispatchQueue(
        label: "com.xiaozhi.ai.audio",
        qos: .userInitiated
    )
    private let stateLock = NSLock()

    private let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48_000,
        channels: 1,
        interleaved: true
    )!

    private var codec: OpusCodec?
    private var converter: AVAudioConverter?
    private var pcmAccumulator = Data()
    private var packetHandler: PacketHandler?
    private var errorHandler: ErrorHandler?
    private var engineConfigured = false
    private var tapInstalled = false
    private var captureActive = false
    private var playbackActive = false

    var isCapturing: Bool {
        stateLock.xzWithLock { captureActive }
    }

    var isPlaying: Bool {
        stateLock.xzWithLock { playbackActive }
    }

    static func requestMicrophonePermission(
        completion: @escaping (Bool) -> Void
    ) {
        AVAudioSession.sharedInstance().requestRecordPermission(completion)
    }

    func startCapture(
        onPacket: @escaping PacketHandler,
        onError: @escaping ErrorHandler
    ) {
        audioQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                guard AVAudioSession.sharedInstance().recordPermission == .granted else {
                    throw AudioError.microphonePermissionDenied
                }
                guard !self.isCapturing else {
                    return
                }

                self.packetHandler = onPacket
                self.errorHandler = onError
                self.pcmAccumulator.removeAll(keepingCapacity: true)
                if self.codec == nil {
                    self.codec = try OpusCodec()
                }
                try self.configureSession()
                try self.configureEngineIfNeeded()

                self.player.stop()
                self.setPlaybackActive(false)

                let input = self.engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                    throw AudioError.invalidInputFormat
                }
                guard let converter = AVAudioConverter(
                    from: inputFormat,
                    to: self.captureFormat
                ) else {
                    throw AudioError.invalidInputFormat
                }
                self.converter = converter

                if self.tapInstalled {
                    input.removeTap(onBus: 0)
                    self.tapInstalled = false
                }
                input.installTap(
                    onBus: 0,
                    bufferSize: 1_024,
                    format: inputFormat
                ) { [weak self] buffer, _ in
                    guard let copy = Self.copy(buffer) else {
                        return
                    }
                    self?.audioQueue.async {
                        self?.processCapturedBuffer(copy)
                    }
                }
                self.tapInstalled = true

                self.engine.prepare()
                try self.engine.start()
                try AVAudioSession.sharedInstance().setActive(
                    true,
                    options: []
                )
                self.setCaptureActive(true)
            } catch {
                self.stopCaptureLocked()
                self.finishSessionIfIdle()
                self.report(error)
            }
        }
    }

    func stopCapture() {
        audioQueue.async { [weak self] in
            guard let self, self.isCapturing else {
                return
            }
            self.stopCaptureLocked()
            self.finishSessionIfIdle()
        }
    }

    func play(_ packet: Data) {
        audioQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                if self.codec == nil {
                    self.codec = try OpusCodec()
                }
                guard let codec = self.codec else {
                    throw AudioError.codec("Opus 编解码器不可用")
                }
                try self.configureSession()
                try self.configureEngineIfNeeded()

                let pcm = try codec.decode(packet)
                let frames = AVAudioFrameCount(
                    pcm.count / MemoryLayout<Int16>.size
                )
                guard frames > 0,
                      let buffer = AVAudioPCMBuffer(
                        pcmFormat: self.playbackFormat,
                        frameCapacity: frames
                      ) else {
                    throw AudioError.invalidInputFormat
                }
                buffer.frameLength = frames
                guard let destination =
                        buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
                    throw AudioError.invalidInputFormat
                }
                pcm.withUnsafeBytes { source in
                    if let base = source.baseAddress {
                        memcpy(destination, base, pcm.count)
                    }
                }

                if !self.engine.isRunning {
                    self.engine.prepare()
                    try self.engine.start()
                }
                if !self.player.isPlaying {
                    self.player.play()
                }
                self.player.scheduleBuffer(buffer, completionHandler: nil)
                self.setPlaybackActive(true)
            } catch {
                self.report(error)
            }
        }
    }

    func stopPlayback() {
        audioQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.player.stop()
            self.setPlaybackActive(false)
            self.finishSessionIfIdle()
        }
    }

    func shutdown() {
        audioQueue.sync {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            player.stop()
            engine.stop()
            setCaptureActive(false)
            setPlaybackActive(false)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            try? AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: []
            )
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
    }

    private func configureEngineIfNeeded() throws {
        guard !engineConfigured else {
            return
        }
        engine.attach(player)
        engine.connect(
            player,
            to: engine.mainMixerNode,
            format: playbackFormat
        )
        engineConfigured = true
    }

    private func processCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isCapturing, let converter else {
            return
        }
        let ratio = captureFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * ratio)
        ) + 64
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: captureFormat,
            frameCapacity: max(capacity, 1)
        ) else {
            return
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(
            to: converted,
            error: &conversionError
        ) { _, outputStatus in
            guard !supplied else {
                outputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            report(AudioError.engine(conversionError.localizedDescription))
            return
        }
        guard status == .haveData || status == .inputRanDry else {
            if status == .error {
                report(AudioError.engine("PCM 重采样失败"))
            }
            return
        }
        guard converted.frameLength > 0 else {
            return
        }

        let audioBuffer = converted.audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else {
            return
        }
        pcmAccumulator.append(
            data.assumingMemoryBound(to: UInt8.self),
            count: Int(audioBuffer.mDataByteSize)
        )

        let frameBytes = 960 * MemoryLayout<Int16>.size
        while pcmAccumulator.count >= frameBytes {
            let frame = pcmAccumulator.prefix(frameBytes)
            pcmAccumulator.removeFirst(frameBytes)
            do {
                guard let codec else {
                    return
                }
                let packet = try codec.encodePCM16LE(Data(frame))
                if !packet.isEmpty {
                    packetHandler?(packet)
                }
            } catch {
                report(error)
                stopCaptureLocked()
                return
            }
        }
    }

    private func stopCaptureLocked() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        converter = nil
        pcmAccumulator.removeAll(keepingCapacity: true)
        setCaptureActive(false)
        if !isPlaying {
            engine.stop()
        }
    }

    private func finishSessionIfIdle() {
        guard !isCapturing, !isPlaying else {
            return
        }
        if engine.isRunning {
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func setCaptureActive(_ value: Bool) {
        stateLock.xzWithLock {
            captureActive = value
        }
    }

    private func setPlaybackActive(_ value: Bool) {
        stateLock.xzWithLock {
            playbackActive = value
        }
    }

    private func report(_ error: Error) {
        let handler = errorHandler
        DispatchQueue.main.async {
            handler?(error)
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(
            buffer.mutableAudioBufferList
        )
        let destination = UnsafeMutableAudioBufferListPointer(
            copy.mutableAudioBufferList
        )
        for index in 0..<min(source.count, destination.count) {
            let sourceBuffer = source[index]
            var destinationBuffer = destination[index]
            destinationBuffer.mDataByteSize = sourceBuffer.mDataByteSize
            if let sourceData = sourceBuffer.mData,
               let destinationData = destinationBuffer.mData {
                memcpy(
                    destinationData,
                    sourceData,
                    Int(sourceBuffer.mDataByteSize)
                )
            }
            destination[index] = destinationBuffer
        }
        return copy
    }
}

private extension NSLock {
    func xzWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
