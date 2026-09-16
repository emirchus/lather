import Foundation

struct SOAPResponse: Identifiable {
    let id: UUID
    var statusCode: Int
    var rawXML: String
    var prettyJSON: String
    var headers: [String: String]
    var duration: TimeInterval
    var receivedAt: Date

    init(
        id: UUID = UUID(),
        statusCode: Int,
        rawXML: String,
        prettyJSON: String,
        headers: [String: String] = [:],
        duration: TimeInterval,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.statusCode = statusCode
        self.rawXML = rawXML
        self.prettyJSON = prettyJSON
        self.headers = headers
        self.duration = duration
        self.receivedAt = receivedAt
    }
}
