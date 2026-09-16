import Foundation

/// Actually performs a SOAP request over the network. Separated from
/// `WorkspaceViewModel` the same way `SOAPTranslating`/`CertificateStoring`
/// are, so the view model stays testable without hitting the network.
protocol SOAPRequestSending {
    func send(_ request: SOAPRequest) async throws -> SOAPResponse
}

/// The exact HTTP headers a request will be sent with — `Content-Type` and
/// `SOAPAction` are added automatically, on top of the user's custom ones.
/// Shared by the sender (to actually set them) and the timeline (to log
/// exactly what went out) so the two can never drift apart.
enum SOAPRequestHeaderBuilder {
    static func headers(for request: SOAPRequest) -> [String: String] {
        var headers = request.headers
        headers["Content-Type"] = "text/xml; charset=utf-8"
        if !request.soapAction.isEmpty {
            headers["SOAPAction"] = "\"\(request.soapAction)\""
        }
        return headers
    }
}

struct URLSessionSOAPRequestSender: SOAPRequestSending {
    struct SendError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let translator: SOAPTranslating

    init(translator: SOAPTranslating = SOAPTranslator()) {
        self.translator = translator
    }

    func send(_ request: SOAPRequest) async throws -> SOAPResponse {
        guard let url = URL(string: request.endpointURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            throw SendError(message: "The endpoint URL isn't valid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        for (key, value) in SOAPRequestHeaderBuilder.headers(for: request) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = Data(request.xmlBody.utf8)

        // TODO: if `request.selectedCertificateID` is set, attach the client
        // certificate for mTLS (needed for WSAA/AFIP-style endpoints). That
        // requires a custom URLSessionDelegate responding to the
        // `.clientCertificate` URLAuthenticationChallenge with a URLCredential
        // built from a SecIdentity — and, before that, actually turning the
        // PEM cert/key files `CertificateStore` holds into one, which isn't
        // implemented yet. Requests currently send without it.

        let start = Date()
        let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        let duration = Date().timeIntervalSince(start)

        let httpResponse = urlResponse as? HTTPURLResponse
        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse?.allHeaderFields ?? [:] {
            if let stringKey = key as? String, let stringValue = value as? String {
                responseHeaders[stringKey] = stringValue
            }
        }

        let rawXML = String(data: data, encoding: .utf8) ?? "<binary response: \(data.count) bytes>"
        let prettyJSON = (try? translator.xmlToJSON(rawXML)) ?? "⚠️ Couldn't translate the response to JSON."

        return SOAPResponse(
            statusCode: httpResponse?.statusCode ?? 0,
            rawXML: rawXML,
            prettyJSON: prettyJSON,
            headers: responseHeaders,
            duration: duration
        )
    }
}
