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
        
        let schemas = context["schemas"] as? [Context]
        context["schemas"] = schemas?.filter { schema in
            schema["type"] as? String != "Errors"
        }
        
        let bodyPropertySchemas = schemas?.filter { schema in
            return properties.contains(where: { schema["type"] as? String == $0["type"] as? String })
        }
        
        context["bodySchemas"] = bodyPropertySchemas
        
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
                    return "List<\(reference.name)>"
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

    override func getOperationContext(_ operation: Swagger.Operation) -> Context {
        var context = super.getOperationContext(operation)
        if let requirements = context["securityRequirements"] as? [[String: Any?]],
           requirements.contains(where: {
            guard let value = $0["name"] as? String else { return false }
            return value == "OAuth2" || value == "OIDC"
           }) {
            context["authorizationRequired"] = true
        }

        return context
    }
    
    override func getEscapedType(_ name: String) -> String {
        return "`\(name)`"
    }

    override func getEscapedName(_ name: String) -> String {
        return "`\(name)`"
    }
}
