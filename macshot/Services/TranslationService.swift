import Foundation
import NaturalLanguage
import Combine
import SwiftUI
@preconcurrency import Translation

enum TranslationProvider: String {
    case apple = "apple"
    case google = "google"
}

enum TranslationService {

    // MARK: - Provider

    static var provider: TranslationProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "translationProvider"),
               let p = TranslationProvider(rawValue: raw) { return p }
            return .google  // Google by default — Apple requires language pack downloads
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translationProvider") }
    }

    /// Whether Apple Translation is available on this system.
    static var appleTranslationAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Cached Apple language availability — populated on first check,
    /// reused instantly for subsequent popover opens.
    private static var cachedAppleAvailability: [String: Bool]?

    // MARK: - Target language

    static var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: "translateTargetLang") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "translateTargetLang") }
    }

    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh-CN", "Chinese (Simplified)"),
        ("zh-TW", "Chinese (Traditional)"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("nb", "Norwegian"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("sk", "Slovak"),
        ("bg", "Bulgarian"),
        ("hr", "Croatian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]

    /// Check which languages are available for Apple Translation.
    /// Returns a dict of language code → installed status.
    @available(macOS 15.0, *)
    static func checkAppleLanguageAvailability(completion: @escaping ([String: Bool]) -> Void) {
        // Return cache immediately if available
        if let cached = cachedAppleAvailability {
            completion(cached)
            return
        }

        Task {
            let availability = LanguageAvailability()
            let allLocales = availableLanguages.map { (code: $0.code, locale: appleLocale(from: $0.code)) }

            // Find the first installed pair to get a known-installed "probe" language.
            // Then check all remaining languages against that probe — O(n) instead of O(n²).
            var installed: [String: Bool] = [:]
            var probeLocale: Locale.Language?
            var probeCode: String?

            // Quick scan: find any installed pair
            outerLoop: for (i, lang) in allLocales.enumerated() {
                for other in allLocales[(i+1)...] {
                    let status = await availability.status(from: lang.locale, to: other.locale)
                    if status == .installed {
                        installed[lang.code] = true
                        installed[other.code] = true
                        probeLocale = lang.locale
                        probeCode = lang.code
                        break outerLoop
                    }
                }
            }

            // Check remaining languages against the probe
            if let probe = probeLocale, let pc = probeCode {
                for lang in allLocales where installed[lang.code] != true {
                    // Check both directions since the probe→lang direction
                    // might not be valid but lang→probe could be
                    let toStatus = await availability.status(from: probe, to: lang.locale)
                    let fromStatus = await availability.status(from: lang.locale, to: probe)
                    installed[lang.code] = (toStatus == .installed || fromStatus == .installed)
                }
                // Ensure the probe itself is marked
                installed[pc] = true
            }

            // Any language not checked stays false
            for lang in allLocales where installed[lang.code] == nil {
                installed[lang.code] = false
            }

            await MainActor.run {
                // Only cache if we found at least one installed language.
                // If the Translation framework wasn't ready (e.g. right after
                // launch), all languages come back as not-installed — don't
                // cache that or the popover stays empty for the whole session.
                if installed.values.contains(true) {
                    cachedAppleAvailability = installed
                }
                completion(installed)
            }
        }
    }

    // MARK: - Translate a batch of strings (auto-detect source)

    /// Translates multiple strings using the selected provider.
    /// Calls completion on the main queue.
    static func translateBatch(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard !texts.isEmpty else {
            completion(.success([]))
            return
        }

        if #available(macOS 15.0, *), provider == .apple {
            translateBatchApple(texts: texts, targetLang: targetLang, completion: completion)
        } else {
            translateBatchGoogle(texts: texts, targetLang: targetLang, completion: completion)
        }
    }

    // MARK: - Google Translate (unofficial endpoint)

    /// Longest `q` (in characters, before percent-encoding) sent in one GET.
    /// Percent-encoded accented text can triple in size; this keeps the URL
    /// well under the ~16 KB limit Google accepts.
    static let googleChunkCharacterLimit = 1800

    /// Translates the whole batch with as few requests as possible: lines are
    /// joined with "\n" into chunks and sent one chunk at a time. Firing one
    /// request per OCR line in parallel is what gets the unofficial endpoint
    /// to answer with a 429 "Sorry..." HTML page instead of JSON.
    private static func translateBatchGoogle(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let finish: (Result<[String], Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        let chunks = googleChunks(for: texts, limit: googleChunkCharacterLimit)
        var results = Array(repeating: "", count: texts.count)
        for (i, text) in texts.enumerated()
        where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results[i] = text
        }

        func translateLinesSequentially(_ indices: [Int], lines: [String], done: @escaping (Error?) -> Void) {
            func step(_ k: Int) {
                guard k < indices.count else { done(nil); return }
                translateOneGoogle(text: lines[k], targetLang: targetLang) { result in
                    switch result {
                    case .failure(let error): done(error)
                    case .success(let t):
                        results[indices[k]] = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        step(k + 1)
                    }
                }
            }
            step(0)
        }

        func run(_ chunkIndex: Int) {
            guard chunkIndex < chunks.count else {
                finish(.success(results))
                return
            }
            let indices = chunks[chunkIndex]
            let lines = indices.map { googleLine(texts[$0]) }
            translateOneGoogle(text: lines.joined(separator: "\n"), targetLang: targetLang) { result in
                switch result {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let translated):
                    if let split = splitGoogleLines(translated, expected: lines.count) {
                        for (k, i) in indices.enumerated() { results[i] = split[k] }
                        run(chunkIndex + 1)
                    } else {
                        // Google merged or split lines: translate this chunk
                        // line by line (sequentially, never in parallel).
                        translateLinesSequentially(indices, lines: lines) { error in
                            if let error { finish(.failure(error)) } else { run(chunkIndex + 1) }
                        }
                    }
                }
            }
        }

        run(0)
    }

    /// One line of input with internal line breaks flattened, so "\n" only
    /// ever separates batch entries.
    static func googleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Groups the indices of non-empty texts into chunks whose joined length
    /// stays under `limit`. A single text longer than `limit` gets its own chunk.
    static func googleChunks(for texts: [String], limit: Int) -> [[Int]] {
        var chunks: [[Int]] = []
        var current: [Int] = []
        var length = 0
        for (i, text) in texts.enumerated() {
            let line = googleLine(text)
            guard !line.isEmpty else { continue }
            let added = line.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty, length + added > limit {
                chunks.append(current)
                current = []
                length = 0
            }
            current.append(i)
            length += line.count + (current.count > 1 ? 1 : 0)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Splits a translated chunk back into its lines. Returns nil when the
    /// line count doesn't match, so the caller can fall back to per-line.
    static func splitGoogleLines(_ translated: String, expected: Int) -> [String]? {
        let parts = translated
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var lines = parts
        while lines.count > expected, lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count == expected, !lines.contains(where: { $0.isEmpty }) else { return nil }
        return lines
    }

    /// Extracts the translated text from a `translate_a/single?dt=t` body.
    /// The body is `[[["out","in",…],["out2","in2",…],…], null, "es", …]`;
    /// segment shapes vary (extra fields, nulls, transliteration rows without
    /// output), and some edges prefix the JSON with `)]}'`.
    static func parseGoogleResponse(_ data: Data) -> Result<String, TranslationError> {
        var body = data
        if let text = String(data: data, encoding: .utf8) {
            var trimmed = Substring(text).drop(while: { $0.isWhitespace })
            if trimmed.hasPrefix(")]}'") { trimmed = trimmed.dropFirst(4) }
            let lower = trimmed.prefix(64).lowercased()
            if lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") {
                return .failure(.blocked)
            }
            body = Data(trimmed.utf8)
        }
        guard let root = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else {
            return .failure(.parseError)
        }
        // Some variants answer with a bare string or ["text", "lang"].
        if let s = root as? String { return s.isEmpty ? .failure(.emptyResult) : .success(s) }
        guard let top = root as? [Any], let first = top.first else { return .failure(.parseError) }
        if let s = first as? String { return s.isEmpty ? .failure(.emptyResult) : .success(s) }
        if first is NSNull { return .failure(.emptyResult) }
        guard let segments = first as? [Any] else { return .failure(.parseError) }
        let translated = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return translated.isEmpty ? .failure(.emptyResult) : .success(translated)
    }

    private static func translateOneGoogle(
        text: String,
        targetLang: String,
        attempt: Int = 0,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl",     value: "auto"),
            URLQueryItem(name: "tl",     value: targetLang),
            URLQueryItem(name: "dt",     value: "t"),
            URLQueryItem(name: "ie",     value: "UTF-8"),
            URLQueryItem(name: "oe",     value: "UTF-8"),
            URLQueryItem(name: "q",      value: text),
        ]
        // URLComponents leaves "+" and "&"-adjacent characters alone in some
        // positions; encode "+" explicitly so it isn't read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            completion(.failure(TranslationError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(TranslationError.network(error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let retryable = status == 429 || status >= 500
            if retryable, attempt < 2 {
                let delay = attempt == 0 ? 1.5 : 4.0
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    translateOneGoogle(text: text, targetLang: targetLang,
                                       attempt: attempt + 1, completion: completion)
                }
                return
            }
            if status == 429 {
                completion(.failure(TranslationError.rateLimited))
                return
            }
            guard (200..<300).contains(status) else {
                completion(.failure(TranslationError.httpStatus(status)))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(TranslationError.noData))
                return
            }
            completion(parseGoogleResponse(data).mapError { $0 as Error })
        }.resume()
    }

    // MARK: - Apple Translation (macOS 15.0+ via SwiftUI bridge)

    @available(macOS 15.0, *)
    private static func translateBatchApple(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let target = appleLocale(from: targetLang)

        // Auto-detect source language to avoid Apple's "Choose Language" dialog
        let combined = texts.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)

        guard let detected = recognizer.dominantLanguage else {
            // Can't detect language (single word, ambiguous text). Report on the
            // main thread — this is invoked from a background OCR queue and the
            // completion handler mutates overlay UI (the success path below also
            // hops to main).
            DispatchQueue.main.async {
                completion(.failure(TranslationError.appleTranslation("Could not detect source language. Try selecting more text.")))
            }
            return
        }

        let source = Locale.Language(identifier: detected.rawValue)
        let config = TranslationSession.Configuration(source: source, target: target)
        // Must dispatch to main — TranslationBridge adds a SwiftUI view which requires main thread
        DispatchQueue.main.async {
            TranslationBridge.shared.translate(texts: texts, configuration: config, completion: completion)
        }
    }

    /// Map our language codes to Apple's Locale.Language.
    @available(macOS 15.0, *)
    private static func appleLocale(from code: String) -> Locale.Language {
        switch code {
        case "zh-CN": return Locale.Language(identifier: "zh-Hans")
        case "zh-TW": return Locale.Language(identifier: "zh-Hant")
        case "nb":    return Locale.Language(identifier: "no")
        default:      return Locale.Language(identifier: code)
        }
    }
}

// MARK: - SwiftUI bridge for Apple Translation

/// Uses a hidden SwiftUI view with .translationTask() to obtain a TranslationSession.
/// This is the supported way to use the Translation framework from AppKit.
@available(macOS 15.0, *)
@MainActor
final class TranslationBridge: ObservableObject {
    static let shared = TranslationBridge()

    @Published var config: TranslationSession.Configuration?
    private var hostingView: NSView?
    private var pendingTexts: [String] = []
    private var pendingCompletion: ((Result<[String], Error>) -> Void)?

    private var translationID: UUID?

    func translate(
        texts: [String],
        configuration: TranslationSession.Configuration,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        // Cancel any in-flight translation before starting a new one
        if pendingCompletion != nil {
            cleanup()
        }

        let thisID = UUID()
        translationID = thisID
        pendingTexts = texts
        pendingCompletion = completion

        // Create hidden SwiftUI view and attach to a window
        let view = TranslationBridgeView(bridge: self)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: -1, y: -1, width: 1, height: 1)
        if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
            window.contentView?.addSubview(hosting)
        }
        hostingView = hosting

        // Setting config triggers .translationTask
        config = configuration

        // Timeout: if session doesn't respond in 10s, report error
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.translationID == thisID, self.pendingCompletion != nil else { return }
            let completion = self.pendingCompletion
            self.cleanup()
            completion?(.failure(TranslationError.appleTranslation("Apple Translation timed out. The language pack may need to be downloaded in System Settings.")))
        }
    }

    fileprivate func sessionReady(_ session: TranslationSession) {
        // Ignore stale sessions from cancelled translations
        guard pendingCompletion != nil else { return }
        let texts = pendingTexts
        let completion = pendingCompletion
        let activeID = translationID
        Task {
            do {
                var results = Array(repeating: "", count: texts.count)
                for (i, text) in texts.enumerated() {
                    // Bail if a new translation was started while we're iterating
                    let stillActive = await MainActor.run { self.translationID == activeID }
                    guard stillActive else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        results[i] = text
                        continue
                    }
                    let response = try await session.translate(trimmed)
                    results[i] = response.targetText
                }
                await MainActor.run {
                    guard self.translationID == activeID else { return }
                    self.cleanup()
                    completion?(.success(results))
                }
            } catch {
                await MainActor.run {
                    guard self.translationID == activeID else { return }
                    self.cleanup()
                    let desc = error.localizedDescription
                    let msg = "Apple Translation failed: \(desc). You can switch to Google Translate in Settings."
                    completion?(.failure(TranslationError.appleTranslation(msg)))
                }
            }
        }
    }

    private func cleanup() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        pendingTexts = []
        pendingCompletion = nil
        config = nil
    }
}

@available(macOS 15.0, *)
private struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.config) { session in
                await MainActor.run {
                    bridge.sessionReady(session)
                }
            }
    }
}

enum TranslationError: LocalizedError {
    case badURL, noData, parseError, emptyResult
    case rateLimited, blocked
    case httpStatus(Int)
    case network(String)
    case appleTranslation(String)
    var errorDescription: String? {
        let fallback = "Try again in a minute, or switch to Apple Translation in Settings."
        switch self {
        case .badURL:      return "Invalid translation URL"
        case .noData:      return "No response from Google Translate. \(fallback)"
        case .parseError:  return "Google Translate sent a response that couldn't be read. \(fallback)"
        case .emptyResult: return "Google Translate returned no text for this selection."
        case .rateLimited: return "Google Translate is limiting requests right now (HTTP 429). \(fallback)"
        case .blocked:     return "Google Translate refused the request (it answered with a web page instead of a translation). \(fallback)"
        case .httpStatus(let code): return "Google Translate is unavailable (HTTP \(code)). \(fallback)"
        case .network(let msg): return "Couldn't reach Google Translate: \(msg)"
        case .appleTranslation(let msg): return msg
        }
    }
}
