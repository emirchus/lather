import Foundation
import Observation

@Observable
final class WorkspaceViewModel {
    enum ResponseTab: String, CaseIterable, Identifiable {
        case prettyJSON = "Pretty JSON"
        case rawXML = "Raw XML"
        case headers = "Headers"
        case timeline = "Timeline"

        var id: String { rawValue }
    }

    var request: SOAPRequest
    var response: SOAPResponse?
    var isSending: Bool = false
    var selectedResponseTab: ResponseTab = .prettyJSON

    let certificateStore: CertificateStoring
    private let translator: SOAPTranslating
    private let requestSender: SOAPRequestSending

    /// Send history, keyed by request — so switching to another request in
    /// the sidebar and back doesn't wipe what you already sent.
    private var timelineEntriesByRequestID: [SOAPRequest.ID: [RequestTimelineEntry]] = [:]

    var timeline: [RequestTimelineEntry] {
        timelineEntriesByRequestID[request.id] ?? []
    }

    init(
        request: SOAPRequest = SOAPRequest(name: "Untitled Request"),
        translator: SOAPTranslating = SOAPTranslator(),
        certificateStore: CertificateStoring = KeychainCertificateStore(),
        requestSender: SOAPRequestSending? = nil
    ) {
        self.request = request
        self.translator = translator
        self.certificateStore = certificateStore
        self.requestSender = requestSender ?? URLSessionSOAPRequestSender(translator: translator)
    }

    func load(_ request: SOAPRequest) {
        self.request = request
        self.response = nil
    }

    func clearTimeline() {
        timelineEntriesByRequestID[request.id] = []
    }

    /// Resolves any `{{variable}}` placeholders in the URL, SOAPAction,
    /// headers, and body against `activeVariables` before sending — the
    /// editor's own `request.xmlBody` keeps its placeholders untouched, so
    /// it stays a reusable template rather than being clobbered with
    /// one-off resolved values.
    func send(activeVariables: [String: String] = [:]) {
        guard !isSending else { return }
        let template = request
        var snapshot = template
        snapshot.endpointURL = VariableSubstitution.resolve(template.endpointURL, using: activeVariables)
        snapshot.soapAction = VariableSubstitution.resolve(template.soapAction, using: activeVariables)
        snapshot.xmlBody = VariableSubstitution.resolve(template.xmlBody, using: activeVariables)
        snapshot.headers = template.headers.mapValues { VariableSubstitution.resolve($0, using: activeVariables) }
        let sentHeaders = SOAPRequestHeaderBuilder.headers(for: snapshot)
        let sentAt = Date()
        isSending = true

        Task {
            defer { isSending = false }
            do {
                let result = try await requestSender.send(snapshot)
                recordTimelineEntry(
                    for: snapshot,
                    sentAt: sentAt,
                    sentHeaders: sentHeaders,
                    statusCode: result.statusCode,
                    responseHeaders: result.headers,
                    responseBody: result.rawXML,
                    duration: result.duration,
                    errorMessage: nil
                )
                // The user may have switched to a different request while
                // this was in flight — don't attach a stale response to it.
                if request.id == snapshot.id {
                    response = result
                }
            } catch {
                recordTimelineEntry(
                    for: snapshot,
                    sentAt: sentAt,
                    sentHeaders: sentHeaders,
                    statusCode: nil,
                    responseHeaders: [:],
                    responseBody: "",
                    duration: Date().timeIntervalSince(sentAt),
                    errorMessage: error.localizedDescription
                )
                if request.id == snapshot.id {
                    let message = "⚠️ \(error.localizedDescription)"
                    response = SOAPResponse(statusCode: 0, rawXML: message, prettyJSON: message, headers: [:], duration: 0)
                }
            }
        }
    }

    private func recordTimelineEntry(
        for snapshot: SOAPRequest,
        sentAt: Date,
        sentHeaders: [String: String],
        statusCode: Int?,
        responseHeaders: [String: String],
        responseBody: String,
        duration: TimeInterval,
        errorMessage: String?
    ) {
        let entry = RequestTimelineEntry(
            timestamp: sentAt,
            endpointURL: snapshot.endpointURL,
            soapAction: snapshot.soapAction,
            requestHeaders: sentHeaders,
            requestBody: snapshot.xmlBody,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            duration: duration,
            errorMessage: errorMessage
        )
        timelineEntriesByRequestID[snapshot.id, default: []].insert(entry, at: 0)
    }

    /// The request's XML payload translated to clean JSON (Layer 3) — used to
    /// (re)populate the JSON editor whenever it's derived fresh from Layer 2
    /// (entering the tab, or switching requests), or a human-readable error
    /// if the XML isn't well-formed.
    func jsonPreview() -> String {
        do {
            return try translator.xmlToJSON(request.xmlBody)
        } catch {
            return "⚠️ \(error.localizedDescription)"
        }
    }

    /// Pushes an edit made in the JSON editor (Layer 3) back into `request.xmlBody`
    /// (Layer 2), which stays the one source of truth for what's actually sent.
    /// Invalid JSON is left alone — `xmlBody` keeps its last valid value until
    /// the edit becomes valid again, rather than getting clobbered.
    @discardableResult
    func applyEditedJSON(_ json: String) -> Bool {
        guard let xml = try? translator.jsonToXML(json, operationName: request.name) else { return false }
        request.xmlBody = xml
        return true
    }
}
