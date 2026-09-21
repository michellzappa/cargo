import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

/// A small lifecycle wrapper around SwiftNIO's maintained HTTP/1 server
/// pipeline. HTTP framing and parsing remain NIO's responsibility.
final class CargoHTTPServer: @unchecked Sendable {
    struct Configuration: Sendable {
        let host: String
        let port: Int

        static let defaultPort = 39817
        static let localhost = Self(host: "127.0.0.1", port: defaultPort)
        static let localNetwork = Self(host: "0.0.0.0", port: defaultPort)
    }

    typealias Responder = @Sendable (CargoAPIRequest) async -> CargoAPIResponse

    private let configuration: Configuration
    private let responder: Responder
    private let group: MultiThreadedEventLoopGroup
    private var serverChannel: Channel?
    private var stopped = false

    init(configuration: Configuration = .localhost, responder: @escaping Responder) {
        self.configuration = configuration
        self.responder = responder
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    var localAddress: SocketAddress? {
        serverChannel?.localAddress
    }

    func start() throws {
        guard serverChannel == nil, !stopped else { return }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            // A restart while a client is connected leaves its sockets in
            // TIME_WAIT; without this the port is unbindable for ~2 minutes.
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [responder] channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withPipeliningAssistance: false,
                    withErrorHandling: true
                ).flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(
                        CargoHTTPHandler(responder: responder)
                    )
                }
            }

        serverChannel = try bootstrap.bind(
            host: configuration.host,
            port: configuration.port
        ).wait()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let serverChannel {
            try? serverChannel.close().wait()
            self.serverChannel = nil
        }
        try? group.syncShutdownGracefully()
    }

    deinit {
        stop()
    }
}

private final class CargoHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private static let maximumBodyBytes = 256 * 1024

    private let responder: CargoHTTPServer.Responder
    private var requestHead: HTTPRequestHead?
    private var requestBody = ByteBuffer()
    private var requestBodyBytes = 0
    private var responseStarted = false

    init(responder: @escaping CargoHTTPServer.Responder) {
        self.responder = responder
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !responseStarted else { return }

        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBody.clear()
            requestBodyBytes = 0
        case .body(var buffer):
            requestBodyBytes += buffer.readableBytes
            guard requestBodyBytes <= Self.maximumBodyBytes else {
                responseStarted = true
                writeError(
                    statusCode: 413,
                    message: "The request body is too large.",
                    context: context
                )
                return
            }
            requestBody.writeBuffer(&buffer)
        case .end:
            guard let requestHead else {
                responseStarted = true
                writeError(statusCode: 400, message: "Malformed HTTP request.", context: context)
                return
            }
            responseStarted = true
            let request = CargoAPIRequest(
                method: requestHead.method.rawValue,
                uri: requestHead.uri,
                headers: Self.headers(from: requestHead.headers),
                body: Data(requestBody.readBytes(length: requestBody.readableBytes) ?? [])
            )
            let responder = self.responder
            let writer = CargoHTTPResponseWriter(handler: self, context: context)
            Task {
                let response = await responder(request)
                writer.write(response)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        requestBody = context.channel.allocator.buffer(capacity: 0)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    fileprivate func write(_ response: CargoAPIResponse, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json; charset=utf-8")
        headers.add(name: "Content-Length", value: String(response.body.count))
        headers.add(name: "Cache-Control", value: "no-store")
        headers.add(name: "Connection", value: "close")
        headers.add(name: "X-Request-ID", value: response.requestID)

        let head = HTTPResponseHead(
            version: .http1_1,
            status: status(for: response.statusCode),
            headers: headers
        )
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let writer = CargoHTTPResponseWriter(handler: self, context: context)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { [writer] _ in
            writer.close()
        }
    }

    private func writeError(
        statusCode: Int,
        message: String,
        context: ChannelHandlerContext
    ) {
        let body = Data(#"{"ok":false,"error":{"code":"bad_request","message":"\#(message)"}}"#.utf8)
        write(
            CargoAPIResponse(
                statusCode: statusCode,
                requestID: UUID().uuidString.lowercased(),
                body: body
            ),
            context: context
        )
    }

    private func status(for code: Int) -> HTTPResponseStatus {
        switch code {
        case 200: .ok
        case 400: .badRequest
        case 401: .unauthorized
        case 404: .notFound
        case 405: .methodNotAllowed
        case 409: .conflict
        case 413: .payloadTooLarge
        default: .internalServerError
        }
    }

    private static func headers(from headers: HTTPHeaders) -> [String: String] {
        var result: [String: String] = [:]
        for header in headers {
            result[header.name.lowercased()] = header.value
        }
        return result
    }
}

private final class CargoHTTPResponseWriter: @unchecked Sendable {
    private weak var handler: CargoHTTPHandler?
    private let context: ChannelHandlerContext

    init(handler: CargoHTTPHandler, context: ChannelHandlerContext) {
        self.handler = handler
        self.context = context
    }

    func write(_ response: CargoAPIResponse) {
        context.eventLoop.execute { [self] in
            guard let handler = self.handler else { return }
            handler.write(response, context: self.context)
        }
    }

    func close() {
        context.close(promise: nil)
    }
}
