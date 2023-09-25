import Foundation
import Swagger

public class KotlinFormatter: CodeFormatter {
    
    var disallowedKeywords: [String] {
        return [
            "as",
            "as?",
            "break",
            "class",
            "continue",
            "do",
            "else",
            "false",
            "for",
            "fun",
            "if",
            "in",
            "!in",
            "interface",
            "is",
            "!is",
            "null",
            "object",
            "package",
            "return",
            "super",
            "this",
            "throw",
            "true",
            "try",
            "typealias",
            "typeof",
            "val",
            "var",
            "when",
            "while",
        ]
    }

    override var disallowedNames: [String] { return disallowedKeywords }
    override var disallowedTypes: [String] { return disallowedKeywords }
    
    override func getSpecContext() -> Context {
        var context = super.getSpecContext()
        
        let requestProperties: [[Context]] = spec.operations.compactMap{
            guard let requestBody = $0.requestBody else { return nil }
            guard let defaultSchema = requestBody.value.content.defaultSchema else { return nil }
            return defaultSchema.properties.map { getPropertyContext($0) }
        }
        let properties = requestProperties.flatMap { $0 }
        
        let schemas = context["schemas"] as? [Context] ?? []
        var filteredSchemas = schemas.filter { schema in
            schema["type"] as? String != "Errors"
        }
        
        for index in filteredSchemas.indices {
            let schemaContext = filteredSchemas[index]
            var resourceType = getResourceType(context: schemaContext)
            
            if resourceType == nil {
                let type = (schemaContext["properties"] as? [Context])?.first?["type"] as? String
                let schema = spec.components.schemas.first(where: {$0.name == type})
                if let schema = schema {
                    let context = getSchemaContent(schema)
                    resourceType = getResourceType(context: context)
                } else {
                    let allProperties = schemaContext["allProperties"] as? [Context]
                    let type = allProperties?.first(where: {$0["name"] as? String == "type"})?["type"] as? String
                    let referencedSchema = spec.components.schemas.first(where: {$0.name == type})
                    if let referencedSchema = referencedSchema {
                        let referencedContext = getSchemaContent(referencedSchema)
                        resourceType = getResourceType(context: referencedContext)
                    }
                }
            }
            
            filteredSchemas[index]["resourceType"] = resourceType
            
            var relationships = filteredSchemas[index]["relationships"] as? [Context] ?? []
            for index in relationships.indices {
                var newProperties: [Context] = []
                
                (relationships[index]["properties"] as? [Context] ?? []).forEach{ property in
                    let type = property["type"] as? String
                    let name = property["name"]
                    let hasMany = (property["properties"] as? [Context])?.first(where: {$0["name"] as? String == "data"})?["isArray"]
                    
                    var component = spec.components.schemas.first(where: {$0.name.lowercased() == type?.lowercased()})
                    if component == nil {
                        let schema = (property["schemas"] as? [Context])?.first
                        let enums = (schema?["enums"] as? [Context])?.first?["enums"] as? [Context]
                        let enumValue = (enums?.first?["value"] as? String)?.lowercased()
                        component = spec.components.schemas.first(where: {$0.name.lowercased() == enumValue})
                    }
                    
                    if let component = component {
                        if case let .array(arraySchema) = component.value.type {
                            // Is a list of a relationship schema (HasMany) e.g. PaymentTokens
                            // Get list item schema
                            if case let .single(arraySchemaItems) = arraySchema.items {
                                let schema = spec.components.schemas.first(where: {$0.name == arraySchemaItems.type.reference?.name})
                                if let schema = schema {
                                    var context = getSchemaContent(schema)
                                    context["name"] = name
                                    context["hasMany"] = hasMany
                                    newProperties.append(context)
                                }
                            }
                        } else {
                            let dataProperties = component.value.properties.first(where: {$0.name == "data"})?.schema.properties
                            let raw = property["raw"] as? Context
                            let reference = raw?["$ref"] as? String
                            let last = reference?.split(separator: "/").last
                            
                            if dataProperties == nil && last != nil {
                                // Discount relationship
                                let referenceType = String(last!)
                                let referenceComponent = schemas.first(where: {$0["type"] as? String == referenceType})
                                let referenceProperties = referenceComponent?["properties"] as? [Context]
                                let hasMany = referenceProperties?.first(where: {$0["name"] as? String == "data"})?["isArray"]
                                let schema = spec.components.schemas.first(where: {$0.name == type})
                                if let schema = schema {
                                    var context = getSchemaContent(schema)
                                    context["name"] = name
                                    context["hasMany"] = hasMany
                                    newProperties.append(context)
                                }
                            } else {
                                let type = dataProperties?.first(where: {$0.name == "type"})
                                let enumValue = type?.enumValue?.cases.first as? String
                                if let enumValue = enumValue {
                                    // Is relationship reference class e.g. PaymentMethodVendorRelationship
                                    // Find correct schema e.g. PaymentMethodVendor
                                    let schema = spec.components.schemas.first(where: {$0.name.lowercased() == enumValue.lowercased()})
                                    if let schema = schema {
                                        var context = getSchemaContent(schema)
                                        context["name"] = name
                                        context["hasMany"] = hasMany
                                        newProperties.append(context)
                                    }
                                } else {
                                    // Is already the correct schema e.g. GasStation
                                    var context = getSchemaContent(component)
                                    context["name"] = name
                                    context["hasMany"] = hasMany
                                    newProperties.append(context)
                                }
                            }
                        }
                    }
                }
                
                relationships[index]["properties"] = newProperties
            }
            
            filteredSchemas[index]["relationships"] = relationships
        }
        
        context["schemas"] = filteredSchemas
        
        let bodyPropertySchemas = schemas.filter { schema in
            return properties.contains(where: { schema["type"] as? String == $0["type"] as? String })
        }
        
        context["bodySchemas"] = bodyPropertySchemas
        
        // Add resources to successResponse
        var operations = context["operations"] as? [Context] ?? []
        for index in operations.indices {
            let successResponse = operations[index]["successResponse"] as? Context
            var successResponseType: String? = nil
            
            if let successResponse = successResponse {
                let successResponseSchema = successResponse["schema"] as? Context
                let schema = (successResponseSchema?["properties"] as? [Context])?.first
                
                successResponseType = schema?["type"] as? String
                if successResponseType == nil {
                    successResponseType = (successResponseSchema)?["type"] as? String
                }
                
                if let schema = schema {
                    let resources = getResources(schemaContext: schema, allSchemas: filteredSchemas)
                    operations[index]["resources"] = Array(Set(resources)).sorted()
                }
            }
            
            if successResponseType == "File" {
                successResponseType = "ResponseBody"
            }
            
            if let responseType = successResponseType {
                let schema = spec.components.schemas.first(where: {$0.name.lowercased() == responseType.lowercased()})
                let type = schema?.value.properties.first(where: {$0.name == "data"})?.schema.type
                if case .array = type {
                    // Add List to response type if data is an array e.g. RegionalPrices should be List<RegionalPrices>
                    successResponseType = "List<\(responseType)>"
                }
            }
            
            operations[index]["successResponseType"] = successResponseType ?? "ResponseBody"
        }
        
        context["operations"] = operations
        
        return context
    }
    
    private func getResourceType(context: Context) -> String? {
        let firstSchema = (context["schemas"] as? [Context])?.first
        let firstEnum = (context["enums"] as? [Context])?.first ?? (firstSchema?["enums"] as? [Context])?.first ?? (context["enum"] as? Context)
        let enumValue = (firstEnum?["enums"] as? [Context])?.first
        
        return enumValue?["value"] as? String
    }
    
    private func getResources(schemaContext: Context, allSchemas: [Context], allResources: [String] = []) -> [String] {
        var newAllResources = allResources
        let schemaType = schemaContext["type"] as? String
        let schema = spec.components.schemas.first(where: {$0.name == schemaType})
        
        var relationships: [Context] = []
        if let schema = schema {
            if case let .array(arraySchema) = schema.value.type {
                if case let .single(arraySchemaItems) = arraySchema.items {
                    // successResponse is a list/typealias PaymentMethods
                    let schema = allSchemas.first(where: {$0["type"] as? String == arraySchemaItems.type.reference?.name})
                    if let schema = schema {
                        relationships = schema["relationships"] as? [Context] ?? []
                    }
                }
            } else {
                // successResponse is an object e.g. PaymentMethod
                let schema = allSchemas.first(where: {$0["type"] as? String == schema.name})
                if let schema = schema {
                    relationships = schema["relationships"] as? [Context] ?? []
                }
            }
        }
        
        relationships
            .flatMap({$0["properties"] as? [Context] ?? []})
            .forEach({
                let type = $0["type"] as? String
                if let type = type {
                    if (!newAllResources.contains(type)) {
                        newAllResources.append(type)
                        newAllResources.append(contentsOf: getResources(schemaContext: $0, allSchemas: allSchemas, allResources: newAllResources))
                    }
                }
            })
        
        return newAllResources
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
            return "Boolean"
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
                case .dateTime: return "Date"
                case .date: return "Date"
                case .email, .hostname, .ipv4, .ipv6, .password: return "String"
                case .uri: return "Uri"
                case .uuid: return "String"
                }
            case .other: return "String"
            }
        case let .number(item):
            guard let format = item.format else {
                return "Double"
            }
            switch format {
            case .double, .decimal: return "Double"
            case .float: return "Float"
            }
        case .integer(_):
            return "Int"
        case let .array(arraySchema):
            switch arraySchema.items {
            case let .single(schema):
                let typeString = getSchemaType(name: name, schema: schema, checkEnum: checkEnum)
                return "List<\(typeString)>"
            case let .multiple(schemas):
                let typeString = getSchemaType(name: name, schema: schemas.first!, checkEnum: checkEnum)
                return "List<\(typeString)>"
            }
        case let .object(schema):
            if let additionalProperties = schema.additionalProperties {
                let typeString = getSchemaType(name: name, schema: additionalProperties, checkEnum: checkEnum)
                return "Map<String, \(typeString)>"
            } else if schema.properties.isEmpty {
                let anyType = templateConfig.getStringOption("anyType") ?? "Any"
                return "Map<String, \(anyType)>"
            } else {
                return escapeType(name.upperCamelCased())
            }
        case let .reference(reference):
            let firstProperty = reference.component.value.properties.first
            let firstPropertyName = firstProperty?.name
            if (firstPropertyName == "data") {
                let type = firstProperty?.schema.metadata.type
                if case .array = type {
                    let schemaType = reference.component.value.type.object?.properties.first?.schema.type
                    if case .array(let arraySchema) = schemaType, case .single(let singleItem) = arraySchema.items {
                        let enumValue = singleItem.type.object?.properties.first(where: {$0.name == "type"})?.schema.metadata.enumValues?.first as? String
                        let referencesSchemaName = spec.components.schemas.first(where: {$0.name.lowercased() == enumValue?.lowercased()})?.name as? String
                        if let referencesSchemaName {
                            return referencesSchemaName
                        }
                    }
                }
            }
            return getSchemaTypeName(reference.component)
        case .any:
            return templateConfig.getStringOption("anyType") ?? "Any"
        default:
            return "Any"
        }
    }
    
    override func getName(_ name: String) -> String {
        var name = name.replacingOccurrences(of: "^-(.+)", with: "$1_Descending", options: .regularExpression)
        name = name.lowerCamelCased()
        return escapeName(name)
    }
    
    override func getSchemaContext(_ schema: Schema) -> Context {
        var context = super.getSchemaContext(schema)
        
        var isPrimitiveType: Bool {
            switch schema.type {
            case .boolean, .number, .integer: return true
            default: return false
            }
        }
        context["isPrimitiveType"] = isPrimitiveType
        
        if let objectSchema = schema.type.object,
           let additionalProperties = objectSchema.additionalProperties {
            context["additionalPropertiesType"] = getSchemaType(name: "Anonymous", schema: additionalProperties)
        }
        
        let properties = context["properties"] as? [Context]
        context["allProperties"] = properties
        
        let names = properties?.compactMap { $0["name"] as? String } ?? []
        let data = properties?.first(where: { $0["type"] as? String == "Data" })
        
        context["isResource"] = ["id", "type"].allSatisfy(names.contains) || data != nil
        context["attributes"] = properties?.filter({($0["name"] as! String) == "attributes"})
        context["relationships"] = properties?.filter({($0["name"] as! String) == "relationships"})
        context["properties"] = properties?.filter({
            ($0["name"] as! String) != "id" &&
            ($0["name"] as! String) != "type" &&
            ($0["name"] as! String) != "attributes" &&
            ($0["name"] as! String) != "relationships" &&
            ($0["type"] as! String) != "Data"
        })
        
        return context
    }
    
    override func getSchemaContent(_ schema: ComponentObject<Schema>) -> Context {
        var context = super.getSchemaContent(schema)
        
        if (schema.value.properties.first?.name == "data") {
            context["isResource"] = true
        }
        
        return context
    }

    override func getParameterContext(_ parameter: Parameter) -> Context {
        var context = super.getParameterContext(parameter)
        
        let type = context["type"] as! String
        context["optionalType"] = type + (parameter.required ? "" : "? = null")
        context["isAnyType"] = type.contains("Any")
        
        return context
    }

    override func getRequestBodyContext(_ requestBody: PossibleReference<RequestBody>) -> Context {
        var context = super.getRequestBodyContext(requestBody)
        
        let type = context["type"] as! String
        context["optionalType"] = type + (requestBody.value.required ? "" : "? = null")
    
        return context
    }

    override func getPropertyContext(_ property: Property) -> Context {
        var context = super.getPropertyContext(property)
        
        let type = context["type"] as! String
        context["optionalType"] = type + (property.nullable ? "? = null" : "")
        context["isAnyType"] = type.contains("Any")
        
        return context
    }

    override func getResponseContext(_ response: OperationResponse) -> Context {
        var context = super.getResponseContext(response)
        
        let type = context["type"] as? String ?? ""
        context["isAnyType"] = type.contains("Any")
        context["acceptHeaders"] = response.response.value.content?.mediaItems.keys.map{$0}
        context["acceptHeaderEnums"] = response.response.value.content?.mediaItems.keys.map{$0.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "+", with: "_").uppercased()}
        
        return context
    }

    override func getEscapedType(_ name: String) -> String {
        return "`\(name)`"
    }

    override func getEscapedName(_ name: String) -> String {
        return "`\(name)`"
    }
}
