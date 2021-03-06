{% include "Common/Includes/Header.stencil" %}

import Foundation

public enum RequestValidationResult {
    case success(URLRequest)
    case failure(Error)
}

public struct AnyResponseValue: APIResponseValue, CustomDebugStringConvertible, CustomStringConvertible {

    public typealias SuccessType = Any

    public let statusCode: Int
    public let successful: Bool
    public let response: Any
    public let responseEnum: Any
    public let success: Any?

    public init(statusCode: Int, successful: Bool, response: Any, responseEnum: Any, success: Any?) {
        self.statusCode = statusCode
        self.successful = successful
        self.response = response
        self.responseEnum = responseEnum
        self.success = success
    }

    public init(statusCode: Int, data: Data, decoder: ResponseDecoder) throws {
        fatalError()
    }

    public var description:String {
        return "\(responseEnum)"
    }

    public var debugDescription: String {
        if let debugDescription = responseEnum as? CustomDebugStringConvertible {
            return debugDescription.debugDescription
        } else {
            return "\(responseEnum)"
        }
    }
}

extension APIResponseValue {
    public func asAny() -> AnyResponseValue {
        return AnyResponseValue(statusCode: statusCode, successful: successful, response: response, responseEnum: self, success: success)
    }
}
