import Foundation

/// One "Send" attempt: a snapshot of exactly what went out and what came
/// back (or the error, if it never got a response). Kept per-request so
/// switching between requests in the sidebar doesn't lose each one's history.
struct RequestTimelineEntry: Identifiable {
    let id: UUID
    let timestamp: Date

    let endpointURL: String
    let soapAction: String
    let requestHeaders: [String: String]
    let requestBody: String

    let statusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: String
    let duration: TimeInterval
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        endpointURL: String,
        soapAction: String,
        requestHeaders: [String: String],
        requestBody: String,
        statusCode: Int?,
        responseHeaders: [String: String],
        responseBody: String,
        duration: TimeInterval,
        errorMessage: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endpointURL = endpointURL
        self.soapAction = soapAction
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
        self.errorMessage = errorMessage
    }

    var isSuccess: Bool {
        guard let statusCode else { return false }
        return (200..<400).contains(statusCode)
    }
}
