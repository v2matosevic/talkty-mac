import Foundation

/// Cloud transcription backed by OpenRouter's audio API. Encodes the finished
/// 16 kHz mono float samples to a WAV container, POSTs it to
/// `/api/v1/audio/transcriptions`, and returns the transcript.
///
/// This is the opt-in "high accuracy" backend; the local whisper.cpp engine stays
/// the privacy-first default. Cloud is NOT offline and costs per use. The selected
/// `ModelSpec` carries the OpenRouter model slug (`openRouterModelId`).
public final class CloudTranscriber: @unchecked Sendable {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!

    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Constants.cloudTranscriptionTimeout
        cfg.timeoutIntervalForResource = Constants.cloudTranscriptionTimeout + 10
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// Transcribe samples via OpenRouter. `language` "auto"/"" → omit so the model
    /// auto-detects. Cancellation (ESC) propagates through the calling Task.
    /// Transient failures (rate limit, gateway hiccup, dropped connection) are retried
    /// once after a short pause instead of failing the take.
    public func transcribe(samples: [Float], modelId: String, language: String,
                           apiKey: String) async -> TranscriptionResult {
        let audioSeconds = Double(samples.count) / Constants.sampleRate
        Log.info("CLOUD transcription: model=\(modelId) audio=\(String(format: "%.1f", audioSeconds))s lang=\(language)")

        guard !apiKey.isEmpty else {
            return .failure("OpenRouter API key not set. Add it in Settings.")
        }
        guard !samples.isEmpty else { return TranscriptionResult(text: "", duration: 0) }

        // OpenRouter's upstream provider caps a single file near 60s: warn rather
        // than silently truncate; chunking longer audio is a future enhancement.
        if audioSeconds > Constants.cloudMaxAudioSeconds {
            Log.warning("Cloud audio is \(Int(audioSeconds))s, over OpenRouter's ~\(Int(Constants.cloudMaxAudioSeconds))s/request limit; the call may time out.")
        }

        guard let request = buildRequest(samples: samples, modelId: modelId, language: language, apiKey: apiKey) else {
            return .failure("Failed to encode cloud request.")
        }

        let (first, transient) = await attempt(request)
        guard !first.success, transient, !Task.isCancelled else { return first }
        Log.warning("Cloud transcription: transient failure (\(first.errorMessage ?? "?")), retrying once")
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return .cancelled }
        let (second, _) = await attempt(request)
        return second
    }

    private func buildRequest(samples: [Float], modelId: String, language: String, apiKey: String) -> URLRequest? {
        let wav = Self.encodeWav(samples, sampleRate: Int(Constants.sampleRate))
        var payload: [String: Any] = [
            "model": modelId,
            "input_audio": ["data": wav.base64EncodedString(), "format": "wav"],
            // Deterministic to match the local engine's zero-temperature behaviour.
            "temperature": 0,
        ]
        let lang = language.lowercased()
        if !lang.isEmpty && lang != "auto" { payload["language"] = lang }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional OpenRouter attribution headers.
        request.setValue(Constants.repoURL, forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Talkty", forHTTPHeaderField: "X-Title")
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = body
        return request
    }

    /// One HTTP attempt. `transient` marks failures worth one retry.
    private func attempt(_ request: URLRequest) async -> (TranscriptionResult, transient: Bool) {
        let t0 = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let dur = -t0.timeIntervalSinceNow
            guard let http = response as? HTTPURLResponse else {
                return (.failure("Cloud transcription: no HTTP response."), true)
            }
            guard (200..<300).contains(http.statusCode) else {
                let transient = http.statusCode == 429 || (500...599).contains(http.statusCode)
                return (.failure(Self.describeError(http.statusCode, data)), transient)
            }
            guard let text = Self.extractText(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.warning("Cloud returned empty/unparseable text: \(Self.preview(data))")
                return (.failure("Cloud transcription returned no text."), false)
            }
            Log.info("Cloud transcription ok in \(String(format: "%.2f", dur))s, \(text.count) chars")
            return (TranscriptionResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines), duration: dur), false)
        } catch is CancellationError {
            return (.cancelled, false)
        } catch let urlError as URLError where urlError.code == .cancelled {
            return (.cancelled, false)
        } catch let urlError as URLError where urlError.code == .timedOut {
            return (.failure("Cloud transcription timed out after \(Int(Constants.cloudTranscriptionTimeout))s."), true)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            return (.failure("Cloud transcription failed: the connection was lost."), true)
        } catch {
            Log.error("Cloud transcription failed: \(error)")
            return (.failure("Cloud transcription failed: \(error.localizedDescription)"), false)
        }
    }

    /// Pulls the transcript out of OpenRouter's `{ "text": "...", "usage": {...} }`.
    private static func extractText(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let usage = obj["usage"] as? [String: Any], let cost = usage["cost"] as? Double {
            Log.info("Cloud request cost: $\(String(format: "%.6f", cost))")
        }
        return obj["text"] as? String
    }

    private static func describeError(_ status: Int, _ body: Data) -> String {
        Log.error("OpenRouter HTTP \(status): \(preview(body))")
        switch status {
        case 401: return "Invalid OpenRouter API key."
        case 402: return "OpenRouter credits exhausted. Top up your account."
        case 429: return "OpenRouter rate limit hit. Try again shortly."
        default: return "Cloud error \(status)."
        }
    }

    private static func preview(_ data: Data) -> String {
        let s = String(decoding: data, as: UTF8.self)
        return s.count <= 300 ? s : String(s.prefix(300)) + "…"
    }

    /// Encodes float PCM samples (-1…1) into a 16-bit mono WAV byte buffer. The local
    /// pipeline keeps audio as float; the cloud API wants an encoded container.
    static func encodeWav(_ samples: [Float], sampleRate: Int) -> Data {
        let bitsPerSample = 16, channels = 1
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * MemoryLayout<Int16>.size

        var data = Data(capacity: 44 + dataSize)
        func append(_ str: String) { data.append(contentsOf: str.utf8) }
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        appendLE(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        appendLE(UInt32(16))                 // PCM fmt chunk size
        appendLE(UInt16(1))                  // audio format = PCM
        appendLE(UInt16(channels))
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(byteRate))
        appendLE(UInt16(blockAlign))
        appendLE(UInt16(bitsPerSample))
        append("data")
        appendLE(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            appendLE(Int16(clamped * Float(Int16.max)))
        }
        return data
    }
}
