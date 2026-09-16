import Foundation
import UniformTypeIdentifiers

struct ClientCertificate: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case pem
        case crt
        case key

        var contentType: UTType {
            UTType(filenameExtension: rawValue) ?? .data
        }
    }

    let id: UUID
    var name: String
    var kind: Kind
    var fileURL: URL

    init(id: UUID = UUID(), name: String, kind: Kind, fileURL: URL) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileURL = fileURL
    }
}
