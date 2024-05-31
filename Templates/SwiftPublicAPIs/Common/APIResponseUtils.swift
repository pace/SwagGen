{% include "Common/Includes/Header.stencil" %}

import Foundation

public protocol APIResponseValue: CustomDebugStringConvertible, CustomStringConvertible {
    associatedtype SuccessType{% if options.codableResponses %} : Codable{% endif %}
    var statusCode: Int { get }
    var successful: Bool { get }
    var response: Any { get }
    init(statusCode: Int, data: Data, decoder: ResponseDecoder) throws
    var success: SuccessType? { get }
}

public enum APIResponseResult<SuccessType, FailureType>: CustomStringConvertible, CustomDebugStringConvertible {
    case success(SuccessType)
    case failure(FailureType)

    public var value: Any {
        switch self {
        case .success(let value): return value
        case .failure(let value): return value
        }
    }

    public var successful: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }

    public var description: String {
        return "\(successful ? "success" : "failure")"
    }

    public var debugDescription: String {
        return "\(description):\n\(value)"
    }
}
