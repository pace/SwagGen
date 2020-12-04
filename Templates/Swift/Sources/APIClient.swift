{% include "Includes/Header.stencil" %}

import Foundation

/// Manages and sends APIRequests
public class APIClient {

    public static var `default` = APIClient(baseURL: {% if options.baseURL %}"{{ options.baseURL }}"{% elif defaultServer %}{{ options.name }}.Server.{{ defaultServer.name }}{% else %}""{% endif %})

    /// A list of RequestBehaviours that can be used to monitor and alter all requests
    public var behaviours: [RequestBehaviour] = []

    /// The base url prepended before every request path
    public var baseURL: String

    /// The UrlSession used for each request
    public var session: URLSession

    /// These headers will get added to every request
    public var defaultHeaders: [String: String]

    public var jsonDecoder = JSONDecoder()
    public var jsonEncoder = JSONEncoder()

    public var decodingQueue = DispatchQueue(label: "apiClient", qos: .utility, attributes: .concurrent)

    public init(baseURL: String, configuration: URLSessionConfiguration = .default, defaultHeaders: [String: String] = [:], behaviours: [RequestBehaviour] = []) {
        self.baseURL = baseURL
        self.behaviours = behaviours
        self.defaultHeaders = defaultHeaders
        jsonDecoder.dateDecodingStrategy = .custom(dateDecoder)
        jsonEncoder.dateEncodingStrategy = .formatted(POIAPI.dateEncodingFormatter)
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: OperationQueue())
    }

    /// Makes a network request
    ///
    /// - Parameters:
    ///   - request: The API request to make
    ///   - behaviours: A list of behaviours that will be run for this request. Merged with APIClient.behaviours
    ///   - completionQueue: The queue that complete will be called on
    ///   - complete: A closure that gets passed the APIResponse
    /// - Returns: A cancellable request. Not that cancellation will only work after any validation RequestBehaviours have run
    @discardableResult
    public func makeRequest<T>(_ request: APIRequest<T>, behaviours: [RequestBehaviour] = [], completionQueue: DispatchQueue = DispatchQueue.main, complete: @escaping (APIResponse<T>) -> Void) -> CancellableRequest? {
        // create composite behaviour to make it easy to call functions on array of behaviours
        let requestBehaviour = RequestBehaviourGroup(request: request, behaviours: self.behaviours + behaviours)

        // create the url request from the request
        var urlRequest: URLRequest
        do {
            urlRequest = try request.createURLRequest(baseURL: baseURL, encoder: jsonEncoder)
        } catch {
            let error = APIClientError.requestEncodingError(error)
            requestBehaviour.onFailure(error: error)
            let response = APIResponse<T>(request: request, result: .failure(error))
            complete(response)
            return nil
        }

        // add the default headers
        if urlRequest.allHTTPHeaderFields == nil {
            urlRequest.allHTTPHeaderFields = [:]
        }
        for (key, value) in defaultHeaders {
            urlRequest.allHTTPHeaderFields?[key] = value
        }

        urlRequest = requestBehaviour.modifyRequest(urlRequest)

        let cancellableRequest = CancellableRequest(request: request.asAny())

        requestBehaviour.validate(urlRequest) { result in
            switch result {
            case .success(let urlRequest):
                self.makeNetworkRequest(request: request, urlRequest: urlRequest, cancellableRequest: cancellableRequest, requestBehaviour: requestBehaviour, completionQueue: completionQueue, complete: complete)
            case .failure(let error):
                let error = APIClientError.validationError(error)
                let response = APIResponse<T>(request: request, result: .failure(error), urlRequest: urlRequest)
                requestBehaviour.onFailure(error: error)
                complete(response)
            }
        }
        return cancellableRequest
    }

    private func makeNetworkRequest<T>(request: APIRequest<T>, urlRequest: URLRequest, cancellableRequest: CancellableRequest, requestBehaviour: RequestBehaviourGroup, completionQueue: DispatchQueue, complete: @escaping (APIResponse<T>) -> Void) {
        requestBehaviour.beforeSend()
        if request.service.isUpload {
            let body = NSMutableData()
            let boundary = "---Boundary" + "\(Int(Date().timeIntervalSince1970))"

            for (key, value) in request.formParameters {
                body.appendString("--\(boundary)\r\n")
                if let file = value as? UploadFile {
                    switch file.type {
                    case let .url(url):
                        if let fileName = file.fileName, let mimeType = file.mimeType {
                            body.appendString("--\(boundary)\r\n")
                            body.appendString("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(fileName)\"\r\n")
                            body.appendString("Content-Type: \(mimeType)\r\n\r\n")
                            body.appendString(url.absoluteString)
                            body.appendString("\r\n")
                        } else {
                            body.appendString("--\(boundary)\r\n")
                            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                            body.appendString("\(url.absoluteString)\r\n")
                        }
                    case let .data(data):
                        if let fileName = file.fileName, let mimeType = file.mimeType {
                            body.appendString("--\(boundary)\r\n")
                            body.appendString("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(fileName)\"\r\n")
                            body.appendString("Content-Type: \(mimeType)\r\n\r\n")
                            body.append(data)
                            body.appendString("\r\n")
                        } else {
                            body.appendString("--\(boundary)\r\n")
                            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                            body.append(data)
                            body.appendString("\r\n")
                        }
                    }
                } else if let url = value as? URL {
                    body.appendString("--\(boundary)\r\n")
                    body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                    body.appendString("\(url.absoluteString)\r\n")
                } else if let data = value as? Data {
                    body.appendString("--\(boundary)\r\n")
                    body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                    body.append(data)
                    body.appendString("\r\n")
                } else if let string = value as? String {
                    body.appendString("--\(boundary)\r\n")
                    body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                    body.append(Data(string.utf8))
                    body.appendString("\r\n")
                }
            }
            body.appendString("--\(boundary)--\r\n")
        } else {
            let task = self.session.dataTask(with: urlRequest, completionHandler: { [weak self] data, response, error -> Void in
                // Handle response
                self?.decodingQueue.async {
                    guard let response = response as? HTTPURLResponse else {
                        let apiError = APIClientError.networkError(URLRequestError.responseInvalid)
                        let result: APIResult<T> = .failure(apiError)
                        requestBehaviour.onFailure(error: apiError)

                        let response = APIResponse<T>(request: request, result: result, urlRequest: urlRequest)
                        requestBehaviour.onResponse(response: response.asAny())

                        completionQueue.async {
                            complete(response)
                        }

                        return
                    }

                    self?.handleResponse(request: request,
                                         requestBehaviour: requestBehaviour,
                                         data: data,
                                         response: response,
                                         error: error,
                                         urlRequest: urlRequest,
                                         completionQueue: completionQueue,
                                         complete: complete)
                }
            })

            self.decodingQueue.async {
                task.resume()
            }

            cancellableRequest.sessionTask = task
        }
    }

    private func handleResponse<T>(request: APIRequest<T>,
                                   requestBehaviour: RequestBehaviourGroup,
                                   data: Data?,
                                   response: HTTPURLResponse,
                                   error: Error?,
                                   urlRequest: URLRequest,
                                   completionQueue: DispatchQueue,
                                   complete: @escaping (APIResponse<T>) -> Void) {
        let result: APIResult<T>

        if let error = error {
            let apiError = APIClientError.networkError(error)
            result = .failure(apiError)
            requestBehaviour.onFailure(error: apiError)
            let response = APIResponse<T>(request: request, result: result, urlRequest: urlRequest, urlResponse: response, data: data)
            requestBehaviour.onResponse(response: response.asAny())

            completionQueue.async {
                complete(response)
            }
            return
        }

        guard let data = data else { return }

        do {
            let statusCode = response.statusCode
            let decoded = try T(statusCode: statusCode, data: data, decoder: jsonDecoder)
            result = .success(decoded)
            if decoded.successful {
                requestBehaviour.onSuccess(result: decoded.response as Any)
            }
        } catch let error {
            let apiError: APIClientError
            if let error = error as? DecodingError {
                apiError = APIClientError.decodingError(error)
            } else if let error = error as? APIClientError {
                apiError = error
            } else {
                apiError = APIClientError.unknownError(error)
            }

            result = .failure(apiError)
            requestBehaviour.onFailure(error: apiError)
        }

        let response = APIResponse<T>(request: request, result: result, urlRequest: urlRequest, urlResponse: response, data: data)
        requestBehaviour.onResponse(response: response.asAny())

        completionQueue.async {
            complete(response)
        }
    }
}

public class CancellableRequest {
    /// The request used to make the actual network request
    public let request: AnyRequest

    init(request: AnyRequest) {
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

// Helper extension for sending requests
extension APIRequest {

    /// makes a request using the default APIClient. Change your baseURL in APIClient.default.baseURL
    public func makeRequest(complete: @escaping (APIResponse<ResponseType>) -> Void) {
        APIClient.default.makeRequest(self, complete: complete)
    }
}

// Create URLRequest
extension APIRequest {

    /// pass in an optional baseURL, otherwise URLRequest.url will be relative
    public func createURLRequest(baseURL: String = "", encoder: RequestEncoder = JSONEncoder()) throws -> URLRequest {
        let urlString = "\(baseURL)\(path)"

        let queryString = URLEncoding.encodeParams(queryParameters)

        let url = URL(string: urlString + "?" + queryString)!
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

extension CharacterSet { // Got it from Alamofire, because swift CharacterSet includes colons
    /// Creates a CharacterSet from RFC 3986 allowed characters.
    ///
    /// RFC 3986 states that the following characters are "reserved" characters.
    ///
    /// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
    /// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
    ///
    /// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
    /// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
    /// should be percent-escaped in the query string.
    public static let apiURLQueryAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        let encodableDelimiters = CharacterSet(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

        return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
    }()
}

