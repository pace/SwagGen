{% include "Common/Includes/Header.stencil" %}

import Foundation

public extension {{ options.name }}Client {
    private static var urlConfiguration: URLSessionConfiguration {
        .default
    }

    static var custom = {{ options.name }}Client(baseURL: {{ options.name }}Client.default.baseURL, configuration: urlConfiguration)
}

