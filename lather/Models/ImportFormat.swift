import UniformTypeIdentifiers

/// External formats Lather can create a collection from.
enum ImportFormat: String, CaseIterable, Identifiable {
    case postman
    case insomnia
    case wsdl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .postman: "Postman Collection"
        case .insomnia: "Insomnia Collection"
        case .wsdl: "WSDL"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .postman, .insomnia: [.json]
        case .wsdl: [.xml, UTType(filenameExtension: "wsdl") ?? .xml]
        }
    }
}
