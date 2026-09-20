import Foundation
import os

/// Intercepts every request of a session configured with `protocolClasses = [StubURLProtocol.self]`.
/// The handler runs on URLSession's queue; state is behind a lock so Swift 6 is happy.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    enum Reply {
        case response(status: Int, headers: [String: String] = [:], body: Data)
        case error(URLError)
        /// Never completes; the request ends only when the task is cancelled.
        case hang
    }

    struct Recorded: Sendable {
        let request: URLRequest
        let body: Data
    }

    nonisolated(unsafe) private static var state = OSAllocatedUnfairLock<(handler: (@Sendable (URLRequest, Data) -> Reply)?, recorded: [Recorded])>(initialState: (nil, []))

    static func install(_ handler: @escaping @Sendable (URLRequest, Data) -> Reply) {
        state.withLock { $0 = (handler, []) }
    }

    static func recordedRequests() -> [Recorded] {
        state.withLock { $0.recorded }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let handler = Self.state.withLock { state -> (@Sendable (URLRequest, Data) -> Reply)? in
            state.recorded.append(Recorded(request: request, body: body))
            return state.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch handler(request, body) {
        case let .response(status, headers, data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            break
        }
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
