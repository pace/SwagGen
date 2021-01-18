{% include "Common/Includes/Header.stencil" %}

import Foundation

public class {{ options.name }}Request<ResponseType: APIResponseValue> {

    public let service: {{ options.name }}Service<ResponseType>
    public private(set) var queryParameters: [String: Any]
    public private(set) var formParameters: [String: Any]
    public let encodeBody: ((RequestEncoder) throws -> Data)?
    private(set) var headerParameters: [String: String]
    public var customHeaders: [String: String] = [:]
    public var version: String = "{{ info.version }}"

    public var headers: [String: String] {
        return headerParameters.merging(customHeaders) { param, custom in return custom }
    }

    public var path: String {
        return service.path
    }

    public init(service: {{ options.name }}Service<ResponseType>,
                queryParameters: [String: Any] = [:],
                formParameters: [String: Any] = [:],
                headers: [String: String] = [:],
                encodeBody: ((RequestEncoder) throws -> Data)? = nil) {
        self.service = service
        self.queryParameters = queryParameters
        self.formParameters = formParameters
        self.headerParameters = headers
        self.encodeBody = encodeBody
    }
}

extension {{ options.name }}Request: CustomStringConvertible {

    public var description: String {
        var string = "\(service.name): \(service.method) \(path)"
        if !queryParameters.isEmpty {
            string += "?" + queryParameters.map {"\($0)=\($1)"}.joined(separator: "&")
        }
        return string
    }
}

extension {{ options.name }}Request: CustomDebugStringConvertible {

    public var debugDescription: String {
        var string = description
        if let encodeBody = encodeBody,
            let data = try? encodeBody(JSONEncoder()),
            let bodyString = String(data: data, encoding: .utf8) {
            string += "\nbody: \(bodyString)"
        }
        return string
    }
}

public class Cancellable{{ options.name }}Request {
    /// The request used to make the actual network request
    public let request: Any{{ options.name }}Request

    init(request: Any{{ options.name }}Request) {
        self.request = request
    }
    var sessionTask: URLSessionTask?

    /// cancels the request
    public func cancel() {
        if let sessionTask = sessionTask {
            sessionTask.cancel()
        }
    }
}

// Create URLRequest
extension {{ options.name }}Request {

    /// pass in an optional baseURL, otherwise URLRequest.url will be relative
    public func createURLRequest(baseURL: String = "", encoder: RequestEncoder = JSONEncoder()) throws -> URLRequest {
        guard var urlComponents = URLComponents(string: "\(baseURL)/\(version)") else {
            throw APIClientError.requestEncodingError(APIRequestError.encodingURL)
        }

        urlComponents.path += "\(path)"
        urlComponents.percentEncodedQueryItems = URLEncoding.encodeParams(queryParameters).map { URLQueryItem(name: $0.0, value: $0.1) }

        let url = urlComponents.url!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = service.method
        urlRequest.allHTTPHeaderFields = headers

        var formParams = URLComponents()
        for (key, value) in formParameters {
            if String.init(describing: value) != "" {
                formParams.queryItems?.append(URLQueryItem(name: key, value: "\(value)"))
            }
        }
        if !(formParams.queryItems?.isEmpty ?? true) {
            urlRequest.httpBody = formParams.query?.data(using: .utf8)
        }

        if let encodeBody = encodeBody {
            urlRequest.httpBody = try encodeBody(encoder)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }
}
