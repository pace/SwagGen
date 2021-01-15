import JSONUtilities

public struct ArraySchema {
    public let items: ArraySchemaItems
    public let minItems: Int?
    public let maxItems: Int?
    public let additionalItems: Schema?
    public let uniqueItems: Bool

    public enum ArraySchemaItems {
        case single(Schema)
        case multiple([Schema])
    }

    public init(items: ArraySchemaItems,
                minItems: Int? = nil,
                maxItems: Int? = nil,
                additionalItems: Schema? = nil,
                uniqueItems: Bool = false) {
        self.items = items
        self.minItems = minItems
        self.maxItems = maxItems
        self.additionalItems = additionalItems
        self.uniqueItems = uniqueItems
    }
}

extension ArraySchema: JSONObjectConvertible {

    public init(jsonDictionary: JSONDictionary) throws {
        let itemsKey = "items"
        if let single: Schema = jsonDictionary.json(atKeyPath: .key(itemsKey)) {
            items = .single(single)
        } else if let multiple: [Schema] = jsonDictionary.json(atKeyPath: .key(itemsKey)) {
            items = .multiple(multiple)
        } else {
            throw SwaggerError.invalidArraySchema(jsonDictionary)
        }

        minItems = jsonDictionary.json(atKeyPath: "minItems")
        maxItems = jsonDictionary.json(atKeyPath: "maxItems")
        additionalItems = jsonDictionary.json(atKeyPath: "additionalItems")
        uniqueItems = jsonDictionary.json(atKeyPath: "uniqueItems") ?? false
    }
}
