import Foundation

/// Resolves `{{variableName}}` placeholders against the active environment's
/// variables, right before a request is sent.
enum VariableSubstitution {
    /// Replaces every `{{key}}` in `template` with `variables[key]`. A key
    /// with no match (unknown variable, or no active environment) is left
    /// as `{{key}}` — visibly unresolved, rather than silently disappearing.
    static func resolve(_ template: String, using variables: [String: String]) -> String {
        guard !variables.isEmpty, template.contains("{{") else { return template }

        var result = ""
        result.reserveCapacity(template.count)
        var remainder = Substring(template)

        while let openRange = remainder.range(of: "{{") {
            result += remainder[remainder.startIndex..<openRange.lowerBound]
            let afterOpen = remainder[openRange.upperBound...]

            guard let closeRange = afterOpen.range(of: "}}") else {
                // No matching close brace — emit the rest verbatim.
                result += remainder[openRange.lowerBound...]
                remainder = Substring("")
                break
            }

            let key = afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            if let value = variables[key] {
                result += value
            } else {
                result += remainder[openRange.lowerBound..<closeRange.upperBound]
            }
            remainder = afterOpen[closeRange.upperBound...]
        }
        result += remainder

        return result
    }
}
