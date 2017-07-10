//
// Generated by SwagGen
// https://github.com/yonaskolb/SwagGen
//

import Foundation
import JSONUtilities

/** definition with additional properties */
public class ModelWithAdditionalProperties: JSONDecodable, JSONEncodable, PrettyPrintable {

    public var name: String?

    public var additionalProperties: [String: Any] = [:]

    public init(name: String? = nil) {
        self.name = name
    }

    public required init(jsonDictionary: JSONDictionary) throws {
        name = jsonDictionary.json(atKeyPath: "name")

        var additionalProperties = jsonDictionary
        additionalProperties.removeValue(forKey: "name")
        self.additionalProperties = additionalProperties
    }

    public func encode() -> JSONDictionary {
        var dictionary: JSONDictionary = [:]
        if let name = name {
            dictionary["name"] = name
        }

        for (key, value) in additionalProperties {
          dictionary[key] = value
        }
        return dictionary
    }

    public subscript(key: String) -> Any? {
        get {
            return additionalProperties[key]
        }
        set {
            additionalProperties[key] = newValue
        }
    }

    /// pretty prints all properties including nested models
    public var prettyPrinted: String {
        return "\(type(of: self)):\n\(encode().recursivePrint(indentIndex: 1))"
    }
}
