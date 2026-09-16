import Foundation

/// Builds a `Collection` from an external export (Postman, Insomnia) or from
/// a WSDL document.
protocol CollectionImporting {
    func importCollection(from url: URL, format: ImportFormat) throws -> Collection
}

struct CollectionImporter: CollectionImporting {
    struct ImportError: LocalizedError {
        let format: ImportFormat
        let underlying: Error

        var errorDescription: String? {
            "Couldn't import \(format.displayName): \(underlying.localizedDescription)"
        }
    }

    func importCollection(from url: URL, format: ImportFormat) throws -> Collection {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            switch format {
            case .postman:
                return try PostmanCollectionParser.parse(data: data)
            case .insomnia:
                return try InsomniaExportParser.parse(data: data)
            case .wsdl:
                return try makeWSDLCollection(from: data, sourceURL: url)
            }
        } catch {
            throw ImportError(format: format, underlying: error)
        }
    }

    private func makeWSDLCollection(from data: Data, sourceURL: URL) throws -> Collection {
        let result = try WSDLDocumentParser().parse(data: data)
        let requests = result.operations.map { operation -> SOAPRequest in
            let schemaXML = result.inputSkeletonXML(forOperation: operation.name)
            return SOAPRequest(
                name: operation.name,
                endpointURL: result.endpointLocation ?? "",
                soapAction: operation.soapAction,
                xmlBody: schemaXML,
                officialSchemaXML: schemaXML
            )
        }
        return Collection(name: sourceURL.deletingPathExtension().lastPathComponent, requests: requests)
    }
}
