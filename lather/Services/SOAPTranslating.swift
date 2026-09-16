import Foundation

/// Translates between the two editable payload representations: the XML
/// envelope that actually gets sent (Layer 2) and a clean JSON view of it
/// that's also directly editable (Layer 3). Also used, later, for parsing
/// SOAP responses (XML) back into JSON.
protocol SOAPTranslating {
    func xmlToJSON(_ xml: String) throws -> String
    func jsonToXML(_ json: String, operationName: String) throws -> String
}

struct SOAPTranslator: SOAPTranslating {
    struct TranslationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - XML -> JSON

    func xmlToJSON(_ xml: String) throws -> String {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "{}" }

        guard let data = xml.data(using: .utf8) else {
            throw TranslationError(message: "Body isn't valid UTF-8 text.")
        }

        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let root = delegate.root else {
            let description = parser.parserError?.localizedDescription ?? "Invalid XML."
            throw TranslationError(message: "\(description) (line \(parser.lineNumber), column \(parser.columnNumber))")
        }

        return renderJSON(unwrapSOAPEnvelope(root), indent: 0)
    }

    /// If the document root is a SOAP `Envelope`, dig into `Body` and return
    /// its single payload element (or all of them) — showing the operation's
    /// actual data instead of the envelope/header/body wrapper noise.
    private func unwrapSOAPEnvelope(_ node: XMLNode) -> XMLNode {
        guard case .element(let rootName, let rootChildren) = node, rootName.lowercased() == "envelope" else {
            return node
        }
        guard let bodyNode = rootChildren.first(where: { isElement($0, named: "body") }),
              case .element(_, let bodyChildren) = bodyNode
        else {
            return node
        }

        let payloadElements = bodyChildren.filter { if case .element = $0 { return true } else { return false } }
        switch payloadElements.count {
        case 0: return bodyNode
        case 1: return payloadElements[0]
        default: return .element(name: "Body", children: payloadElements)
        }
    }

    private func isElement(_ node: XMLNode, named name: String) -> Bool {
        if case .element(let elementName, _) = node { return elementName.lowercased() == name } else { return false }
    }

    private func renderJSON(_ node: XMLNode, indent: Int) -> String {
        switch node {
        case .text(let string):
            return "\"\(escapeJSON(string))\""

        case .element(_, let children):
            let elementChildren: [(name: String, node: XMLNode)] = children.compactMap {
                if case .element(let name, _) = $0 { return (name, $0) } else { return nil }
            }

            guard !elementChildren.isEmpty else {
                let text = children
                    .compactMap { if case .text(let value) = $0 { value } else { nil } }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\"\(escapeJSON(text))\""
            }

            var order: [String] = []
            var grouped: [String: [XMLNode]] = [:]
            for child in elementChildren {
                if grouped[child.name] == nil { order.append(child.name) }
                grouped[child.name, default: []].append(child.node)
            }

            let pad = String(repeating: "  ", count: indent + 1)
            let closePad = String(repeating: "  ", count: indent)
            let lines = order.map { name -> String in
                let nodes = grouped[name]!
                if nodes.count == 1 {
                    return "\(pad)\"\(name)\": \(renderJSON(nodes[0], indent: indent + 1))"
                }
                let items = nodes.map { "\(pad)  \(renderJSON($0, indent: indent + 2))" }
                return "\(pad)\"\(name)\": [\n" + items.joined(separator: ",\n") + "\n\(pad)]"
            }
            return "{\n" + lines.joined(separator: ",\n") + "\n\(closePad)}"
        }
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - JSON -> XML

    /// Wraps the JSON back into a standard SOAP envelope, with `operationName`
    /// as the root element under `<soapenv:Body>`. This always regenerates a
    /// plain `soapenv:Header`/`Body` wrapper — a custom envelope prefix,
    /// header contents, or attributes hand-edited in the XML tab won't
    /// survive a round trip through JSON.
    func jsonToXML(_ json: String, operationName: String) throws -> String {
        let payload: JSONValue
        do {
            payload = try OrderedJSONParser.parse(json)
        } catch {
            throw TranslationError(message: "Body isn't valid JSON: \(error.localizedDescription)")
        }

        let rootElement = sanitize(elementName: operationName)
        let operationXML = xmlElement(name: rootElement, value: payload)
        let indentedOperationXML = indentLines(operationXML.components(separatedBy: "\n"), by: 2)

        return """
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
          <soapenv:Header/>
          <soapenv:Body>
        \(indentedOperationXML)
          </soapenv:Body>
        </soapenv:Envelope>
        """
    }

    private func indentLines(_ lines: [String], by level: Int) -> String {
        let pad = String(repeating: "  ", count: level)
        return lines.map { $0.isEmpty ? $0 : pad + $0 }.joined(separator: "\n")
    }

    private func xmlElement(name: String, value: JSONValue) -> String {
        switch value {
        case .object(let fields):
            guard !fields.isEmpty else { return "<\(name)/>" }
            let childLines = fields.flatMap { xmlElement(name: sanitize(elementName: $0.0), value: $0.1).components(separatedBy: "\n") }
            return "<\(name)>\n\(indentLines(childLines, by: 1))\n</\(name)>"
        case .array(let items):
            return items.map { xmlElement(name: name, value: $0) }.joined(separator: "\n")
        case .string(let string):
            return "<\(name)>\(escapeXML(string))</\(name)>"
        case .number(let literal):
            return "<\(name)>\(literal)</\(name)>"
        case .bool(let flag):
            return "<\(name)>\(flag ? "true" : "false")</\(name)>"
        case .null:
            return "<\(name)/>"
        }
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// XML element names can't contain spaces or most punctuation; fall back
    /// to a generic name if the operation/key is empty after stripping those.
    private func sanitize(elementName: String) -> String {
        let allowed = elementName.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return allowed.isEmpty ? "value" : allowed
    }

    // MARK: - Shared XML tree

    private indirect enum XMLNode {
        case element(name: String, children: [XMLNode])
        case text(String)
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        private(set) var root: XMLNode?
        private var stack: [(name: String, children: [XMLNode])] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            stack.append((stripPrefix(elementName), []))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].children.append(.text(string))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard let finished = stack.popLast() else { return }
            let node = XMLNode.element(name: finished.name, children: finished.children)
            if stack.isEmpty {
                root = node
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }

        private func stripPrefix(_ name: String) -> String {
            guard let colonIndex = name.firstIndex(of: ":") else { return name }
            return String(name[name.index(after: colonIndex)...])
        }
    }
}
