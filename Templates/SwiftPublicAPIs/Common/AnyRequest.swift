{% include "Common/Includes/Header.stencil" %}

public class Any{{ options.name }}Request: {{ options.name }}Request<AnyResponseValue> {
    private let requestPath: String

    override public var path: String {
        return requestPath
    }

    init<T>(request: {{ options.name }}Request<T>) {
        requestPath = request.path
        super.init(service: request.service.asAny(), queryParameters: request.queryParameters, formParameters: request.formParameters, headers: request.headers, encodeBody: request.encodeBody)
    }
}

extension {{ options.name }}Request {
    public func asAny() -> Any{{ options.name }}Request {
        return Any{{ options.name }}Request(request: self)
    }
}
