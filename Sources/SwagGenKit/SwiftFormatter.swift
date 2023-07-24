import Foundation
import Swagger

public class SwiftFormatter: CodeFormatter {

    var disallowedKeywords: [String] {
        return [
            "Type",
            "Protocol",
            "class",
            "struct",
            "enum",
            "protocol",
            "extension",
            "return",
            "throw",
            "throws",
            "rethrows",
            "public",
            "open",
            "private",
            "fileprivate",
            "internal",
            "let",
            "var",
            "where",
            "guard",
            "associatedtype",
            "deinit",
            "func",
            "import",
            "inout",
            "operator",
            "static",
            "subscript",
            "typealias",
            "case",
            "break",
            "continue",
            "default",
            "defer",
            "do",
            "else",
            "fallthrough",
            "for",
            "if",
            "in",
            "repeat",
            "switch",
            "where",
            "while",
            "as",
            "Any",
            "AnyObject",
            "catch",
            "false",
            "true",
            "is",
            "nil",
            "super",
            "self",
            "Self",
        ]
    }

    var inbuiltTypes: [String] = [
        "Error",
        "Data",
    ]

    override var disallowedNames: [String] { return disallowedKeywords + inbuiltTypes }
    override var disallowedTypes: [String] { return disallowedKeywords + inbuiltTypes }

    let fixedWidthIntegers: Bool

    public override init(spec: SwaggerSpec, templateConfig: TemplateConfig) {
        fixedWidthIntegers = templateConfig.getBooleanOption("fixedWidthIntegers") ?? false
        super.init(spec: spec, templateConfig: templateConfig)
    }

    override func getSpecContext() -> Context {
        var context = super.getSpecContext()

        let result = renameRequestBodyTypes(for: context)
        let schemaTypesToRename = result.1
        context = result.0

        let schemaTypesToDuplicate = schemaTypesToDuplicate(for: context, in: schemaTypesToRename)
        context = renameAndDuplicateRequestSchemas(for: context, schemaTypesToRename: schemaTypesToRename, schemaTypesToDuplicate: schemaTypesToDuplicate)
        context = flattenHierachy(for: context)
        context = resolveRelationships(for: context)

        return context
    }

    private func renameRequestBodyTypes(for context: Context) -> (Context, Set<String>) {
        var context = context
        var schemaTypesToRename: Set<String> = []
        var operations = context["operations"] as? [Context] ?? []

        // Iterate over all request schemas and add `Request` to the model types
        // These model types must not be flattened otherwise the requests won't work
        // Find the type of the `data` property in the `Body` type or the type of the property called `body`
        operations = operations.reduce(into: [], {
            var operation = $1
            let hasBody = operation["hasBody"] as? Bool ?? false

            guard hasBody, var body = operation["body"] as? Context else {
                $0.append(operation)
                return
            }

            var requestSchemas = operation["requestSchemas"] as? [Context] ?? []

            // If there are no request schemas check for property called `body` and its type
            if requestSchemas.isEmpty,
               let bodyName = body["name"] as? String,
               let bodyType = body["type"] as? String,
               bodyName == "body",
               bodyType.hasPrefix(modelPrefix),
               !bodyType.hasSuffix("Request") {

                schemaTypesToRename.insert(bodyType)
                body = newRequestTypeName(for: bodyType, in: body)
                operation["body"] = body
            } else {
                requestSchemas = requestSchemas.reduce(into: [], {
                    var requestSchema = $1
                    let requestSchemaType = requestSchema["type"] as? String ?? ""

                    guard requestSchemaType == "Body" else {
                        $0.append(requestSchema)
                        return
                    }

                    var properties = requestSchema["properties"] as? [Context] ?? []

                    properties = properties.reduce(into: [], {
                        var property = $1

                        // Check for the type of the property called `data`
                        if let propertyName = property["name"] as? String,
                           let propertyType = property["type"] as? String,
                           propertyName == "data",
                           propertyType.hasPrefix(modelPrefix),
                           !propertyType.hasSuffix("Request") {

                            schemaTypesToRename.insert(propertyType)
                            property = newRequestTypeName(for: propertyType, in: property)
                        }

                        $0.append(property)
                    })

                    requestSchema["properties"] = properties
                    $0.append(requestSchema)
                })

                operation["requestSchemas"] = requestSchemas
            }

            $0.append(operation)
        })

        context["operations"] = operations
        return (context, schemaTypesToRename)
    }

    private func newRequestTypeName(for type: String, in context: Context) -> Context {
        var context = context

        let isOptional = context["optional"] as? Bool ?? false
        let newType = "\(type)Request"

        context["type"] = newType
        context["optionalType"] = isOptional ? "\(newType)?" : newType

        return context
    }

    // Look for a response type that is included in the set of types that have to be renamed
    // This means it's a type that is used as request AND response model and therefore has to be duplicated
    private func schemaTypesToDuplicate(for context: Context, in schemaTypesToRename: Set<String>) -> Set<String> {
        var schemaTypesToDuplicate: Set<String> = []
        let operations = context["operations"] as? [Context] ?? []

        // In case the response does not have an enclosing type e.g. Status201
        for operation in operations {
            let responses = operation["responses"] as? [Context] ?? []

            for response in responses {
                guard let responseType = response["type"] as? String, schemaTypesToRename.contains(responseType) else { continue }
                schemaTypesToDuplicate.insert(responseType)
            }
        }

        // In case the response does have an enclosing type
        // Look for type of property named `data`
        for operation in operations {
            let responseSchemas = operation["responseSchemas"] as? [Context] ?? []

            for responseSchema in responseSchemas {
                let properties = responseSchema["properties"] as? [Context] ?? []

                for property in properties {
                    let propertyType = property["type"] as? String ?? ""
                    let polyTypes = (property["polyTypes"] as? [PolyType] ?? []).map { $0.type }.filter { schemaTypesToRename.contains($0) }

                    if schemaTypesToRename.contains(propertyType) {
                        schemaTypesToDuplicate.insert(propertyType)
                    }

                    polyTypes.forEach {
                        schemaTypesToDuplicate.insert($0)
                    }
                }
            }
        }

        return schemaTypesToDuplicate
    }

    // The schemas that are only used as a request model have to be renamed
    // The ones that are also used as a response model have to be duplicated and renamed
    private func renameAndDuplicateRequestSchemas(for context: Context, schemaTypesToRename: Set<String>, schemaTypesToDuplicate: Set<String>) -> Context {
        var context = context
        var schemas = context["schemas"] as? [Context] ?? []

        schemas = schemas.reduce(into: [], {
            var schema = $1
            let schemaType = schema["type"] as? String ?? ""
            let newSchemaType = "\(schemaType)Request"

            if schemaTypesToRename.contains(schemaType) && schemaTypesToDuplicate.contains(schemaType) {
                // Duplicate schema
                var duplicatedSchema = schema
                duplicatedSchema["type"] = newSchemaType
                $0.append(duplicatedSchema)
            } else if schemaTypesToRename.contains(schemaType) {
                // Rename schema
                schema["type"] = newSchemaType
            }

            $0.append(schema)
        })

        context["schemas"] = schemas
        return context
    }

    private func flattenHierachy(for context: Context) -> Context {
        var context = context

        var schemas = context["schemas"] as? [Context] ?? []
        var operations = context["operations"] as? [Context] ?? []

        // Schemas are basically classes / structs / enums (models for requests and responses)
        // Response and Request Models (e.g PCFuelingApproachingResponse, PCFuelingTransactionsRequest)
        schemas = schemas.reduce(into: [], {
            var schema = $1

            let schemaType = schema["type"] as? String ?? ""
            let isRequest = schemaType.hasPrefix(modelPrefix) && schemaType.hasSuffix("Request")

            // Do not flatten schemas of requests
            if !isRequest {
                schema = flattenHierachy(for: schema)
                schema = flattenSchemaContext(for: schema)
            }

            $0.append(schema)
        })

        // Inline response models (e.g FuelingAPIApproachingAtTheForecourt.Response.Status201)
        operations = operations.reduce(into: [], {
            var operation = $1
            var responses = operation["responses"] as? [Context] ?? []

            // The response schemas contain the properties that need to be removed (e.g. included)
            var responseSchemas = operation["responseSchemas"] as? [Context] ?? []

            responses = responses.reduce(into: [], {
                var response = $1

                // NOTE: - For responses the key is 'schema' and not 'schemas'
                if var schema = response["schema"] as? Context {
                    schema = flattenHierachy(for: schema)
                    schema = flattenSchemaContext(for: schema)
                    response["schema"] = schema
                }

                $0.append(response)
            })

            responseSchemas = responseSchemas.reduce(into: [], {
                var responseSchema = $1
                responseSchema = flattenHierachy(for: responseSchema)
                responseSchema = flattenSchemaContext(for: responseSchema)
                $0.append(responseSchema)
            })

            operation["responses"] = responses
            operation["responseSchemas"] = responseSchemas
            $0.append(operation)
        })

        context["schemas"] = schemas
        context["operations"] = operations

        return context
    }

    private func flattenSchemaContext(for context: Context) -> Context {
        var context = context

        let schemas = context["schemas"] as? [Context]
        let properties = context["allProperties"] as? [Context] ?? []
        let enums = context["enums"] as? [Context]

        // Separate relationships property
        // Remove relationship hierarchy level and get all properties
        let relationships = properties.filter { ($0["name"] as! String) == "relationships" }
        let relationshipProperties = relationships.compactMap { $0["allProperties"] as? [Context] }.flatMap { $0 }
        context["relationships"] = relationships

        // Separate attributes property
        // Remove attributes hierarchy level and get all properties
        let attributes = properties.filter { ($0["name"] as! String) == "attributes" }
        let attributeProperties = attributes.compactMap { $0["allProperties"] as? [Context] }.flatMap { $0 }
        let attributeSchemas = attributes.compactMap { $0["schemas"] as? [Context] }.flatMap { $0 }
        let attributeEnums = attributes.compactMap { $0["enums"] as? [Context] }.flatMap { $0 }

        // Remove specified properties
        // Add properties of relationships and attributes to get rid of their hierarchy level
        context["properties"] = filterProperties(properties)
        + relationshipProperties
        + attributeProperties

        // Remove specified optional properties
        let optionalProperties = context["optionalProperties"] as? [Context] ?? []
        context["optionalProperties"] = filterProperties(optionalProperties)

        // Remove specified required properties
        let requiredProperties = context["requiredProperties"] as? [Context] ?? []
        context["requiredProperties"] = filterProperties(requiredProperties)

        // Remove specified schemas (classes etc.)
        // Add schemas of attributes to get rid of its hierarchy level
        context["schemas"] = (schemas ?? []).filter {
            ![
                "Attributes",
                "Relationships"
            ].contains($0["type"] as! String)
        }
        + attributeSchemas

        // Add enums of attributes to get rid of its hierarchy level
        context["enums"] = (enums ?? []) + attributeEnums

        return context
    }

    private func filterProperties(_ properties: [Context]) -> [Context] {
        properties.filter {
            ![
                "attributes",
                "relationships",
                "included"
            ].contains($0["name"] as! String)
        }
    }

    private func resolveRelationships(for context: Context) -> Context {
        var context = context
        var schemas = context["schemas"] as? [Context] ?? []

        for (schemaIndex, schema) in schemas.enumerated() {
            guard let relationships = schema["relationships"] as? [Context],
                  var properties = schema["properties"] as? [Context] else { continue }

            // Go through all the properties of all relationships
            for relationship in relationships {
                guard let allProperties = relationship["allProperties"] as? [Context] else { continue }

                for property in allProperties {
                    let relationshipPropertyName = property["name"] as! String
                    var relationshipPropertyType = property["type"] as! String
                    var relationshipPropertySchema: Context
                    var isArray = false

                    if let innerSchemas = property["schemas"] as? [Context],
                       let innerSchema = innerSchemas.first { // If the Relationship is defined inline
                        relationshipPropertySchema = innerSchema
                    } else { // Else it must be defined as a reference
                        if let props = property["allProperties"] as? [Context], // If it is a nested definition we have to dig deeper for the referenced type name
                           let prop = props.first,
                           !prop.isEmpty {
                            relationshipPropertyType = prop["type"] as! String
                            if prop["isArray"] as! Bool {
                                relationshipPropertyType = relationshipPropertyType.replacingOccurrences(of: "[", with: "")
                                relationshipPropertyType = relationshipPropertyType.replacingOccurrences(of: "]", with: "")
                            }
                        }
                        guard let innerSchema = schemas.first(where: { $0["type"] as! String == relationshipPropertyType }) else {
                            fatalError("Failed to retrieve correct type name for the relationship: \(relationshipPropertyName) with type \(relationshipPropertyType)")
                        }
                        if let innerInnerSchemas = innerSchema["schemas"] as? [Context],
                           let innerInnerSchema = innerInnerSchemas.first { // Check if referenced relation is nested again
                            if let innerProperties = innerSchema["allProperties"] as? [Context],
                               let innerProperty = innerProperties.first,
                               let innerIsArray = innerProperty["isArray"] as? Bool { // check if type is nested inside an array
                                isArray = innerIsArray
                            }
                            relationshipPropertySchema = innerInnerSchema
                        } else { // Else the referenced type inside the relation can be derived directly
                            relationshipPropertySchema = innerSchema
                        }
                    }

                    guard let outerEnums = relationshipPropertySchema["enums"] as? [Context],
                       let outerEnum = outerEnums.first,
                       let innerEnums = outerEnum["enums"] as? [Context],
                       let innerEnum = innerEnums.first,
                       let typeName = innerEnum["value"] as? String else {
                        fatalError("Could not retrieve the type for relation \(relationshipPropertyName)")
                    }

                    if let allInnerProperties = property["allProperties"] as? [Context],
                          let innerProperty = allInnerProperties.first {
                        isArray = innerProperty["isArray"] as? Bool ?? false
                    }

                    let type = "\(modelPrefix)\(capitalizeFirstLetter(in: typeName))"

                    guard let propertyIndex = properties.firstIndex(where: { ($0["name"] as! String) == relationshipPropertyName }) else { fatalError() }

                    properties[propertyIndex]["type"] = isArray ? "[\(type)]" : type
                    properties[propertyIndex]["optionalType"] = isArray ? "[\(type)]?" : "\(type)?"
                }
            }

            schemas[schemaIndex]["properties"] = properties
        }

        context["schemas"] = schemas

        return context
    }

    override func getSchemaType(name: String, schema: Schema, checkEnum: Bool = true) -> String {

        var enumValue: String?
        if checkEnum {
            enumValue = schema.getEnum(name: name, description: "").flatMap { getEnumContext($0)["enumName"] as? String }
        }

        if schema.canBeEnum, let enumValue = enumValue {
            return enumValue
        }

        switch schema.type {
        case .boolean:
            return "Bool"
        case let .string(item):
            guard let format = item.format else {
                return "String"
            }
            switch format {
            case let .format(format):
                switch format {
                case .binary: return "File"
                case .byte: return "File"
                case .base64: return "String"
                case .dateTime: return "DateTime"
                case .date: return "DateDay"
                case .email, .hostname, .ipv4, .ipv6, .password: return "String"
                case .uri: return "URL"
                case .uuid: return "ID"
                }
            case .other: return "String"
            }
        case let .number(item):
            guard let format = item.format else {
                return templateConfig.getStringOption("numberType") ?? "Double"
            }
            switch format {
            case .double: return templateConfig.getStringOption("doubleType") ?? "Double"
            case .float: return templateConfig.getStringOption("floatType") ?? "Float"
            case .decimal: return templateConfig.getStringOption("decimalType") ?? "Decimal"
            }
        case let .integer(item):
            guard let format = item.format else {
                return "Int"
            }

            if fixedWidthIntegers {
                switch format {
                case .int32: return "Int32"
                case .int64: return "Int64"
                }
            } else {
                return "Int"
            }
        case let .array(arraySchema):
            switch arraySchema.items {
            case let .single(type):
                let typeString = getSchemaType(name: name, schema: type, checkEnum: checkEnum)
                return checkEnum ? "[\(enumValue ?? typeString)]" : typeString
            case let .multiple(types):
                let typeString = getSchemaType(name: name, schema: types.first!, checkEnum: checkEnum)
                return checkEnum ? "[\(enumValue ?? typeString)]" : typeString
            }
        case let .object(schema):
            if let additionalProperties = schema.additionalProperties {
                let typeString = getSchemaType(name: name, schema: additionalProperties, checkEnum: checkEnum)
                return checkEnum ? "[String: \(enumValue ?? typeString)]" : typeString
            } else if schema.properties.isEmpty {
                let anyType = templateConfig.getStringOption("anyType") ?? "Any"
                return "[String: \(anyType)]"
            } else {
                return escapeType(name.upperCamelCased())
            }
        case let .reference(reference):
            return getSchemaTypeName(reference.component)
        case let .group(groupSchema):
            if groupSchema.schemas.count == 1, let singleGroupSchema = groupSchema.schemas.first {
                //flatten group schemas with only one schema
                return getSchemaType(name: name, schema: singleGroupSchema)
            }

            guard groupSchema.schemas.count <= 11 else {
                return escapeType(name.upperCamelCased())
            }

            var schemas: [String] = []

            for schema in groupSchema.schemas {
                schemas.append(getSchemaType(name: name, schema: schema))
            }

            return "\(name.capitalized)PolyType"

        case .any:
            return templateConfig.getStringOption("anyType") ?? "Any"
        }
    }

    override func getName(_ name: String) -> String {
        var name = name.replacingOccurrences(of: "^-(.+)", with: "$1_Descending", options: .regularExpression)
        name = name.lowerCamelCased()
        return escapeName(name)
    }

    override func getSchemaContext(_ schema: Schema) -> Context {
        var context = super.getSchemaContext(schema)

        if let objectSchema = schema.type.object,
            let additionalProperties = objectSchema.additionalProperties {
            context["additionalPropertiesType"] = getSchemaType(name: "Anonymous", schema: additionalProperties)
        }

        return context
    }

    override func getOperationContext(_ operation: Swagger.Operation) -> Context {
        var context = super.getOperationContext(operation)
        if let operationId = operation.identifier {
            context["fileName"] = escapeType("\(requestPrefix)\(operationId.upperCamelCased())")
        } else {
            let pathParts = operation.path.components(separatedBy: "/")
            var pathName = pathParts.map { $0.upperCamelCased() }.joined(separator: "")
            pathName = pathName.replacingOccurrences(of: "\\{(.*?)\\}", with: "By_$1", options: .regularExpression, range: nil)
            let generatedOperationId = operation.method.rawValue.lowercased() + pathName.upperCamelCased()
            context["fileName"] = escapeType("\(requestPrefix)\(generatedOperationId.upperCamelCased())")
        }

        return context
    }

    override func getPathParamsContext(_ parameter: Parameter) -> Context {
        var context = super.getParameterContext(parameter)

        let type = context["type"] as! String
        let name = context["name"] as! String

        context["optionalType"] = type + (parameter.required ? "" : "?")
        var encodedValue = getEncodedValue(name: getName(name), type: type)

        if case let .schema(schema) = parameter.type,
            case .array = schema.schema.type,
            let collectionFormat = schema.collectionFormat {
            if type != "[String]" {
                encodedValue += ".map({ String(describing: $0) })"
            }
            encodedValue += ".joined(separator: \"\(collectionFormat.separator)\")"
        }
        if !parameter.required {
            if let range = encodedValue.range(of: ".") {
                encodedValue = encodedValue.replacingOccurrences(of: ".", with: "?.", options: [], range: range)
                encodedValue += " ?? \"\""
            }
            if type == "String" {
                encodedValue += " ?? \"\""
            }
        }
        context["encodedValue"] = encodedValue
        context["isAnyType"] = type.contains("Any")
        return context
    }

    override func getParameterContext(_ parameter: Parameter) -> Context {
        var context = super.getParameterContext(parameter)

        let type = context["type"] as! String
        let name = context["name"] as! String

        context["optionalType"] = type + (parameter.required ? "" : "?")
        var encodedValue = getEncodedValue(name: getName(name), type: type)

        if case let .schema(schema) = parameter.type,
            case .array = schema.schema.type,
            let collectionFormat = schema.collectionFormat {
            if type != "[String]" {
                encodedValue += ".map({ String(describing: $0) })"
            }
            encodedValue += ".joined(separator: \"\(collectionFormat.separator)\")"
        }
        if !parameter.required {
            if let range = encodedValue.range(of: ".") {
                encodedValue = encodedValue.replacingOccurrences(of: ".", with: "?.", options: [], range: range)
            }
        }
        context["encodedValue"] = encodedValue
        context["isAnyType"] = type.contains("Any")
        return context
    }

    override func getRequestBodyContext(_ requestBody: PossibleReference<RequestBody>) -> Context {
        var context = super.getRequestBodyContext(requestBody)
        let type = context["type"] as! String
        context["optionalType"] = type + (requestBody.value.required ? "" : "?")
        context["isAnyType"] = type.contains("Any")
        return context
    }

    func getEncodedValue(name: String, type: String) -> String {
        var encodedValue = name

        let jsonTypes = ["Any", "[String: Any]", "Int", "String", "Float", "Double", "Bool"]

        if !jsonTypes.contains(type), !jsonTypes.map({ "[\($0)]" }).contains(type), !jsonTypes.map({ "[String: \($0)]" }).contains(type) {
            if type.hasPrefix("[[") {
                encodedValue += ".map({ $0.encode() })"
            } else if type.hasPrefix("[String: [") {
                encodedValue += ".mapValues({ $0.encode() })"
            } else {
                encodedValue += ".encode()"
            }
        }

        return encodedValue
    }

    override func getPropertyContext(_ property: Property) -> Context {
        var context = super.getPropertyContext(property)

        let type = context["type"] as! String
        let name = context["name"] as! String

        context["optionalType"] = type + (property.nullable ? "?" : "")
        var encodedValue = getEncodedValue(name: getName(name), type: type)

        if !property.required, let range = encodedValue.range(of: ".") {
            encodedValue = encodedValue.replacingOccurrences(of: ".", with: "?.", options: [], range: range)
        }

        context["encodedValue"] = encodedValue
        context["isAnyType"] = type.contains("Any")

        if case .array(let arraySchema) = property.schema.type,
           case .single(let singleArraySchema) = arraySchema.items,
           case .group(let groupSchema) = singleArraySchema.type,
           groupSchema.schemas.count > 1 {
            let schemas: [String] = groupSchema.schemas.map { getSchemaType(name: name, schema: $0) }
            context["isPoly"] = true
            context["polyTypes"] = getPolyTypes(schemas)
            context["polyTypeString"] = "\(name.capitalized)PolyType"
        }

        return context
    }

    override func getPolyTypes(_ schemas: [String]) -> [PolyType] {
        schemas.map {
            let capitalizedName = $0.dropFirst(modelPrefix.count)
            let name = capitalizedName.prefix(1).lowercased() + capitalizedName.dropFirst()
            let type = $0
            return PolyType(name: name, type: type)
        }
    }

    override func getResponseContext(_ response: OperationResponse) -> Context {
        var context = super.getResponseContext(response)
        let type = context["type"] as? String ?? ""
        context["isAnyType"] = type.contains("Any")

        let mediaTypes = response.response.value.content?.mediaItems.keys
        context["acceptHeaders"] = mediaTypes?.compactMap { $0 }
        context["acceptHeadersEnumCases"] = mediaTypes?.compactMap { $0.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "+", with: "_").replacingOccurrences(of: "-", with: "_") }

        return context
    }

    override func getEscapedType(_ name: String) -> String {
        if inbuiltTypes.contains(name) {
            return "\(name)Type"
        }
        return "`\(name)`"
    }

    override func getEscapedName(_ name: String) -> String {
        return "`\(name)`"
    }

    private func capitalizeFirstLetter(in string: String) -> String {
        string.prefix(1).capitalized + string.dropFirst()
    }
}
