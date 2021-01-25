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

    var inbuiltTypes: [String] = [
        "Error",
        "Data",
    ]

    override var disallowedNames: [String] { return disallowedKeywords + inbuiltTypes }
    override var disallowedTypes: [String] { return disallowedKeywords + inbuiltTypes }
    
    override func getSchemaType(name: String, schema: Schema, checkEnum: Bool = true) -> String {
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
            case let .single(type):
                let typeString = getSchemaType(name: name, schema: type, checkEnum: checkEnum)
                return "List<\(typeString)>"
            case let .multiple(types):
                let typeString = getSchemaType(name: name, schema: types.first!, checkEnum: checkEnum)
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
            return getSchemaTypeName(reference.component)
        case .any:
            return templateConfig.getStringOption("anyType") ?? "Any"
        default:
            return "Any"
        }
    }
    
    override func getSchemaContext(_ schema: Schema) -> Context {
        var context = super.getSchemaContext(schema)

        if let objectSchema = schema.type.object,
            let additionalProperties = objectSchema.additionalProperties {
            context["additionalPropertiesType"] = getSchemaType(name: "Anonymous", schema: additionalProperties)
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
        
        return context
    }
    
    override func getEscapedType(_ name: String) -> String {
        return "`\(name)`"
    }

    override func getEscapedName(_ name: String) -> String {
        return "`\(name)`"
    }
}
