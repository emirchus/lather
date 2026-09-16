import Foundation

/// Parses a Postman Collection v2.1 export into a `Collection`. Folders
/// (nested `item` arrays) are flattened — Lather's sidebar has no concept of
/// sub-folders yet, only collections and requests.
enum PostmanCollectionParser {
    static func parse(data: Data) throws -> Collection {
        let decoded = try JSONDecoder().decode(PostmanCollection.self, from: data)
        return Collection(name: decoded.info.name, requests: flatten(items: decoded.item))
    }

    private static func flatten(items: [Item]) -> [SOAPRequest] {
        items.flatMap { item -> [SOAPRequest] in
            if let request = item.request {
                return [makeRequest(name: item.name, request: request)]
            } else if let children = item.item {
                return flatten(items: children)
            } else {
                return []
            }
        }
    }

    private static func makeRequest(name: String, request: Request) -> SOAPRequest {
        var headers: [String: String] = [:]
        var soapAction = ""
        for header in request.header ?? [] {
            if header.key.caseInsensitiveCompare("SOAPAction") == .orderedSame {
                soapAction = header.value
            } else {
                headers[header.key] = header.value
            }
        }

        return SOAPRequest(
            name: name,
            endpointURL: request.url?.rawValue ?? "",
            soapAction: soapAction,
            xmlBody: request.body?.raw ?? "",
            headers: headers
        )
    }

    // MARK: - Wire format

    private struct PostmanCollection: Decodable {
        let info: Info
        let item: [Item]

        struct Info: Decodable {
            let name: String
        }
    }

    private struct Item: Decodable {
        let name: String
        let item: [Item]?
        let request: Request?
    }

    private struct Request: Decodable {
        let header: [Header]?
        let url: URLValue?
        let body: Body?
    }

    private struct Header: Decodable {
        let key: String
        let value: String
    }

    private struct Body: Decodable {
        let raw: String?
    }

    /// Postman's request URL is either a plain string or a detailed object
    /// (`{ "raw": "...", "host": [...], "path": [...] }`); accept both.
    private enum URLValue: Decodable {
        case raw(String)
        case detailed(DetailedURL)

        struct DetailedURL: Decodable {
            let raw: String?
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(), let string = try? container.decode(String.self) {
                self = .raw(string)
            } else {
                self = .detailed(try DetailedURL(from: decoder))
            }
        }

        var rawValue: String {
            switch self {
            case .raw(let value): value
            case .detailed(let value): value.raw ?? ""
            }
        }
    }
}
