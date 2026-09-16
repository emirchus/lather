import Foundation

/// Fetches and parses a WSDL document to discover the operations a SOAP
/// service exposes, so the request editor can offer autocompletion.
protocol WSDLServicing {
    func fetchOperations(fromWSDLURL url: URL) async throws -> [WSDLOperation]
}

struct WSDLService: WSDLServicing {
    func fetchOperations(fromWSDLURL url: URL) async throws -> [WSDLOperation] {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            (data, _) = try await URLSession.shared.data(from: url)
        }
        return try WSDLDocumentParser().parse(data: data).operations
    }
}
