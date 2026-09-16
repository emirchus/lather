import Foundation

/// Parses an Insomnia v4 export (`{ "resources": [...] }`) into a
/// `Collection`. Insomnia exports a flat list of resources linked by
/// `parentId`; folders (`request_group`) are ignored and every `request`
/// resource is flattened into the resulting collection.
enum InsomniaExportParser {
    static func parse(data: Data) throws -> Collection {
        let decoded = try JSONDecoder().decode(Export.self, from: data)
        let workspaceName = decoded.resources.first { $0._type == "workspace" }?.name

        let requests = decoded.resources
            .filter { $0._type == "request" }
            .map(makeRequest)

        return Collection(name: workspaceName ?? "Imported from Insomnia", requests: requests)
    }

    private static func makeRequest(_ resource: Resource) -> SOAPRequest {
        var headers: [String: String] = [:]
        var soapAction = ""
        for header in resource.headers ?? [] {
            if header.name.caseInsensitiveCompare("SOAPAction") == .orderedSame {
                soapAction = header.value
            } else {
                headers[header.name] = header.value
            }
        }

        return SOAPRequest(
            name: resource.name ?? "Untitled Request",
            endpointURL: resource.url ?? "",
            soapAction: soapAction,
            xmlBody: resource.body?.text ?? "",
            headers: headers
        )
    }

    // MARK: - Wire format

    private struct Export: Decodable {
        let resources: [Resource]
    }

    private struct Resource: Decodable {
        let _type: String
        let name: String?
        let url: String?
        let headers: [Header]?
        let body: Body?
    }

    private struct Header: Decodable {
        let name: String
        let value: String
    }

    private struct Body: Decodable {
        let text: String?
    }
}
