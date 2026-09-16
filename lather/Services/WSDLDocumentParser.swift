import Foundation

/// Minimal WSDL 1.1 parser: extracts the SOAP operations declared in a
/// `<binding>` (name + soapAction), the service endpoint address, and —
/// where the WSDL uses rpc/encoded style with inline XSD `complexType`
/// definitions — enough of the `<types>` schema to build an example JSON
/// body per operation. Uses a namespace-aware SAX parser so it works
/// regardless of which XML prefixes (`wsdl:`, `soap:`, `soap12:`, `xsd:`, or
/// none) the document happens to use.
struct WSDLDocumentParser {
    struct Result {
        let operations: [WSDLOperation]
        let endpointLocation: String?
        fileprivate let operationToRequestMessage: [String: String]
        fileprivate let messageParts: [String: [(name: String, typeName: String)]]
        fileprivate let complexTypes: [String: XSDType]

        /// Builds an example SOAP envelope for `operationName` from the WSDL's
        /// message parts and XSD complex types — the "official" schema-driven
        /// reference used to seed a new request and to power the read-only
        /// Schema tab. Doc/literal WSDLs that reference a schema `element`
        /// rather than a `type` on their message parts aren't resolved, and
        /// fall back to an empty `<operationName/>` element.
        func inputSkeletonXML(forOperation operationName: String) -> String {
            let messageName = operationToRequestMessage[operationName] ?? "\(operationName)Request"
            let parts = messageParts[messageName] ?? []
            let operationValue = SkeletonValue.object(parts.map { ($0.name, resolveValue(typeName: $0.typeName, visiting: [])) })
            let operationXML = renderXMLField(name: operationName, value: operationValue, indent: 2)

            return """
            <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
              <soapenv:Header/>
              <soapenv:Body>
            \(operationXML)
              </soapenv:Body>
            </soapenv:Envelope>
            """
        }

        private func resolveValue(typeName rawTypeName: String, visiting: Set<String>) -> SkeletonValue {
            let typeName = stripPrefix(rawTypeName)
            guard !visiting.contains(typeName), let type = complexTypes[typeName] else {
                return primitiveValue(forTypeName: typeName)
            }

            var nextVisiting = visiting
            nextVisiting.insert(typeName)

            switch type {
            case .array(let elementType):
                return .array([resolveValue(typeName: elementType, visiting: nextVisiting)])
            case .fields(let fields):
                let resolved = fields.map { ($0.name, resolveValue(typeName: $0.typeName, visiting: nextVisiting)) }
                return .object(resolved)
            }
        }

        private func primitiveValue(forTypeName typeName: String) -> SkeletonValue {
            switch typeName.lowercased() {
            case "int", "integer", "long", "short", "byte", "unsignedint", "unsignedlong", "nonnegativeinteger":
                return .number("0")
            case "float", "double", "decimal":
                return .number("0.0")
            case "boolean":
                return .bool(false)
            default:
                return .string("")
            }
        }

        private func stripPrefix(_ name: String) -> String {
            guard let colonIndex = name.firstIndex(of: ":") else { return name }
            return String(name[name.index(after: colonIndex)...])
        }

        /// Renders one field as an XML element (or, for `.array`, as several
        /// sibling elements sharing `name` — SOAP repeats the element itself
        /// rather than using a wrapper/index).
        private func renderXMLField(name: String, value: SkeletonValue, indent: Int) -> String {
            let pad = String(repeating: "  ", count: indent)
            switch value {
            case .string(let string):
                return "\(pad)<\(name)>\(string)</\(name)>"
            case .number(let literal):
                return "\(pad)<\(name)>\(literal)</\(name)>"
            case .bool(let flag):
                return "\(pad)<\(name)>\(flag ? "true" : "false")</\(name)>"
            case .object(let fields):
                guard !fields.isEmpty else { return "\(pad)<\(name)/>" }
                let lines = fields.map { renderXMLField(name: $0.0, value: $0.1, indent: indent + 1) }
                return "\(pad)<\(name)>\n" + lines.joined(separator: "\n") + "\n\(pad)</\(name)>"
            case .array(let items):
                guard !items.isEmpty else { return "" }
                return items.map { renderXMLField(name: name, value: $0, indent: indent) }.joined(separator: "\n")
            }
        }
    }

    private indirect enum SkeletonValue {
        case string(String)
        case number(String)
        case bool(Bool)
        case object([(String, SkeletonValue)])
        case array([SkeletonValue])
    }

    fileprivate enum XSDType {
        case fields([(name: String, typeName: String)])
        case array(elementType: String)
    }

    func parse(data: Data) throws -> Result {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }

        return Result(
            operations: delegate.operations,
            endpointLocation: delegate.endpointLocation,
            operationToRequestMessage: delegate.operationToRequestMessage,
            messageParts: delegate.messageParts,
            complexTypes: delegate.complexTypes
        )
    }

    private enum Namespace {
        static let wsdl = "http://schemas.xmlsoap.org/wsdl/"
        static let soap11 = "http://schemas.xmlsoap.org/wsdl/soap/"
        static let soap12 = "http://schemas.xmlsoap.org/wsdl/soap12/"
        static let xsd = "http://www.w3.org/2001/XMLSchema"
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var operations: [WSDLOperation] = []
        private(set) var endpointLocation: String?
        private(set) var operationToRequestMessage: [String: String] = [:]
        private(set) var messageParts: [String: [(name: String, typeName: String)]] = [:]
        private(set) var complexTypes: [String: XSDType] = [:]

        private var targetNamespace = ""
        private var elementStack: [(name: String, namespace: String?)] = []

        // Binding operations (name + soapAction)
        private var currentBindingOperationName: String?
        private var currentBindingOperationSoapAction: String?

        // PortType operations (operation name -> request message name)
        private var currentPortTypeOperationName: String?

        // <message name="X"><part name="Y" type="Z"/></message>
        private var currentMessageName: String?
        private var currentMessageParts: [(name: String, typeName: String)] = []

        // <xsd:complexType name="X"> ... </xsd:complexType>
        private var currentComplexTypeName: String?
        private var currentComplexTypeFields: [(name: String, typeName: String)] = []
        private var currentComplexTypeArrayElement: String?

        private var isInsideBinding: Bool {
            elementStack.contains { $0.name == "binding" && $0.namespace == Namespace.wsdl }
        }

        private var isInsidePortType: Bool {
            elementStack.contains { $0.name == "portType" && $0.namespace == Namespace.wsdl }
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            elementStack.append((elementName, namespaceURI))

            switch (elementName, namespaceURI) {
            case ("definitions", Namespace.wsdl):
                targetNamespace = attributeDict["targetNamespace"] ?? ""

            case ("operation", Namespace.wsdl) where isInsideBinding:
                currentBindingOperationName = attributeDict["name"]
                currentBindingOperationSoapAction = nil

            case ("operation", Namespace.soap11), ("operation", Namespace.soap12):
                if isInsideBinding, currentBindingOperationName != nil {
                    currentBindingOperationSoapAction = attributeDict["soapAction"] ?? ""
                }

            case ("address", Namespace.soap11), ("address", Namespace.soap12):
                if endpointLocation == nil {
                    endpointLocation = attributeDict["location"]
                }

            case ("operation", Namespace.wsdl) where isInsidePortType:
                currentPortTypeOperationName = attributeDict["name"]

            case ("input", Namespace.wsdl):
                if let operationName = currentPortTypeOperationName, let message = attributeDict["message"] {
                    operationToRequestMessage[operationName] = stripPrefix(message)
                }

            case ("message", Namespace.wsdl):
                currentMessageName = attributeDict["name"]
                currentMessageParts = []

            case ("part", Namespace.wsdl):
                if currentMessageName != nil, let name = attributeDict["name"] {
                    let typeName = attributeDict["type"] ?? attributeDict["element"] ?? "string"
                    currentMessageParts.append((name, typeName))
                }

            case ("complexType", Namespace.xsd):
                currentComplexTypeName = attributeDict["name"]
                currentComplexTypeFields = []
                currentComplexTypeArrayElement = nil

            case ("element", Namespace.xsd):
                if currentComplexTypeName != nil, let name = attributeDict["name"] {
                    let typeName = attributeDict["type"] ?? "string"
                    currentComplexTypeFields.append((name, typeName))
                }

            case ("attribute", Namespace.xsd):
                if currentComplexTypeName != nil, attributeDict["ref"] == "SOAP-ENC:arrayType" {
                    let arrayTypeValue = attributeDict.first { $0.key == "arrayType" || $0.key.hasSuffix(":arrayType") }?.value
                    if let arrayTypeValue {
                        currentComplexTypeArrayElement = stripPrefix(arrayTypeValue.replacingOccurrences(of: "[]", with: ""))
                    }
                }

            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch (elementName, namespaceURI) {
            case ("operation", Namespace.wsdl) where isInsideBinding:
                if let name = currentBindingOperationName {
                    operations.append(
                        WSDLOperation(name: name, soapAction: currentBindingOperationSoapAction ?? "", targetNamespace: targetNamespace)
                    )
                }
                currentBindingOperationName = nil
                currentBindingOperationSoapAction = nil

            case ("operation", Namespace.wsdl) where isInsidePortType:
                currentPortTypeOperationName = nil

            case ("message", Namespace.wsdl):
                if let name = currentMessageName {
                    messageParts[name] = currentMessageParts
                }
                currentMessageName = nil
                currentMessageParts = []

            case ("complexType", Namespace.xsd):
                if let name = currentComplexTypeName {
                    if let arrayElement = currentComplexTypeArrayElement {
                        complexTypes[name] = .array(elementType: arrayElement)
                    } else {
                        complexTypes[name] = .fields(currentComplexTypeFields)
                    }
                }
                currentComplexTypeName = nil
                currentComplexTypeFields = []
                currentComplexTypeArrayElement = nil

            default:
                break
            }

            if !elementStack.isEmpty {
                elementStack.removeLast()
            }
        }

        private func stripPrefix(_ name: String) -> String {
            guard let colonIndex = name.firstIndex(of: ":") else { return name }
            return String(name[name.index(after: colonIndex)...])
        }
    }
}
