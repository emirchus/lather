import Foundation

struct WSDLOperation: Identifiable, Hashable {
    let id: UUID
    var name: String
    var soapAction: String
    var targetNamespace: String

    init(id: UUID = UUID(), name: String, soapAction: String, targetNamespace: String) {
        self.id = id
        self.name = name
        self.soapAction = soapAction
        self.targetNamespace = targetNamespace
    }
}
