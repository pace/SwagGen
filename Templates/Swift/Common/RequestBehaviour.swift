{% include "Common/Includes/Header.stencil" %}

import Foundation

public protocol {{ options.name }}RequestBehaviour {

    /// runs first and allows the requests to be modified. If modifying asynchronously use validate
    func modifyRequest(request: Any{{ options.name }}Request, urlRequest: URLRequest) -> URLRequest

    /// validates and modifies the request. complete must be called with either .success or .fail
    func validate(request: Any{{ options.name }}Request, urlRequest: URLRequest, complete: @escaping (RequestValidationResult) -> Void)

    /// called before request is sent
    func beforeSend(request: Any{{ options.name }}Request)

    /// called when request successfuly returns a 200 range response
    func onSuccess(request: Any{{ options.name }}Request, result: Any)

    /// called when request fails with an error. This will not be called if the request returns a known response even if the a status code is out of the 200 range
    func onFailure(request: Any{{ options.name }}Request, urlRequest: URLRequest?, response: HTTPURLResponse, error: APIClientError)

    /// called if the request recieves a network response. This is not called if request fails validation or encoding
    func onResponse(request: Any{{ options.name }}Request, response: Any{{ options.name }}Response)
}

// Provides empty defaults so that each function becomes optional
public extension {{ options.name }}RequestBehaviour {
    func modifyRequest(request: Any{{ options.name }}Request, urlRequest: URLRequest) -> URLRequest { return urlRequest }
    func validate(request: Any{{ options.name }}Request, urlRequest: URLRequest, complete: @escaping (RequestValidationResult) -> Void) {
        complete(.success(urlRequest))
    }
    func beforeSend(request: Any{{ options.name }}Request) {}
    func onSuccess(request: Any{{ options.name }}Request, result: Any) {}
    func onFailure(request: Any{{ options.name }}Request, urlRequest: URLRequest?, response: HTTPURLResponse, error: APIClientError) {}
    func onResponse(request: Any{{ options.name }}Request, response: Any{{ options.name }}Response) {}
}

struct {{ options.name }}RequestBehaviourImplementation: {{ options.name }}RequestBehaviour {
    func onFailure(request: Any{{ options.name }}Request, urlRequest: URLRequest?, response: HTTPURLResponse, error: APIClientError) {
        let url = urlRequest?.url?.absoluteString ?? response.url?.absoluteString ?? "invalid url"
        switch error {
        case .networkError(let error) where (error as NSError).code == NSURLErrorCancelled:
            SDKLogger.i("[{{ options.name }}] Request with url (\(url)) was canceled.")

        default:
            let requestId: String = response.allHeaderFields["request-id"] as? String ?? "unknown"
            SDKLogger.e("[{{ options.name }}] Request (\(url)) with request-id: \(requestId) failed with error: \(error.description)")
        }
    }
}

// Group different RequestBehaviours together
struct {{ options.name }}RequestBehaviourGroup {

    let request: Any{{ options.name }}Request
    let behaviours: [{{ options.name }}RequestBehaviour]

    init<T>(request: {{ options.name }}Request<T>, behaviours: [{{ options.name }}RequestBehaviour]) {
        self.request = request.asAny()
        self.behaviours = behaviours
    }

    func beforeSend() {
        behaviours.forEach {
            $0.beforeSend(request: request)
        }
    }

    func validate(_ urlRequest: URLRequest, complete: @escaping (RequestValidationResult) -> Void) {
        if behaviours.isEmpty {
            complete(.success(urlRequest))
            return
        }

        var count = 0
        var modifiedRequest = urlRequest
        func validateNext() {
            let behaviour = behaviours[count]
            behaviour.validate(request: request, urlRequest: modifiedRequest) { result in
                count += 1
                switch result {
                case .success(let urlRequest):
                    modifiedRequest = urlRequest
                    if count == self.behaviours.count {
                        complete(.success(modifiedRequest))
                    } else {
                        validateNext()
                    }
                case .failure(let error):
                    complete(.failure(error))
                }
            }
        }
        validateNext()
    }

    func onSuccess(result: Any) {
        behaviours.forEach {
            $0.onSuccess(request: request, result: result)
        }
    }

    func onFailure(urlRequest: URLRequest?, response: HTTPURLResponse, error: APIClientError) {
        behaviours.forEach {
            $0.onFailure(request: request, urlRequest: urlRequest, response: response, error: error)
        }
    }

    func onResponse(response: Any{{ options.name }}Response) {
        behaviours.forEach {
            $0.onResponse(request: request, response: response)
        }
    }

    func modifyRequest(_ urlRequest: URLRequest) -> URLRequest {
        var newRequest = urlRequest
        behaviours.forEach {
            newRequest = $0.modifyRequest(request: request, urlRequest: newRequest)
        }

        if let newRequestUrl = newRequest.url {
            newRequest.url = QueryParamHandler.buildUrl(for: newRequestUrl)
        }

        newRequest.setValue(Constants.Tracing.identifier, forHTTPHeaderField: Constants.Tracing.key)

        return newRequest
    }
}

extension {{ options.name }}Service {
    public func asAny() -> {{ options.name }}Service<AnyResponseValue> {
        return {{ options.name }}Service<AnyResponseValue>(id: id, tag: tag, method: method, path: path, hasBody: hasBody, securityRequirements: securityRequirements)
    }
}
