import Foundation

struct SOAPRequest: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var endpointURL: String
    var soapAction: String
    /// The actual SOAP envelope XML that gets sent — the payload the user edits.
    var xmlBody: String
    /// Read-only reference envelope generated from the WSDL schema, if this
    /// request came from a WSDL import. Powers the "Schema" tab and, later,
    /// schema-aware suggestions; never mutated after import.
    var officialSchemaXML: String?
    var selectedCertificateID: ClientCertificate.ID?
    var headers: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        endpointURL: String = "",
        soapAction: String = "",
        xmlBody: String = "",
        officialSchemaXML: String? = nil,
        selectedCertificateID: ClientCertificate.ID? = nil,
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.soapAction = soapAction
        self.xmlBody = xmlBody
        self.officialSchemaXML = officialSchemaXML
        self.selectedCertificateID = selectedCertificateID
        self.headers = headers
    }
}
