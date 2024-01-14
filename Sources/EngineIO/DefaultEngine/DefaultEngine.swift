//
//  DefaultEngine.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public actor DefaultEngine {

    // MARK: Inner types

    public struct Configuration {
        public static let `default` = Configuration()

        public var pingInterval: Int
        public var pingTimeout: Int
        public var maxPayload: Int
        public var addTrailingSlash: Bool
        public var allowEIO3: Bool
        public var allowUpgrades: Bool
        public var allowRequest: ((Request) throws -> Void)?
        public var cookie: CookieOptions?
        public var logLevel: Logger.Level

        public init(pingInterval: Int = 3000, 
                    pingTimeout: Int = 2000,
                    maxPayload: Int = 1000000,
                    addTrailingSlash: Bool = false,
                    allowEIO3: Bool = false,
                    allowUpgrades: Bool = true,
                    allowRequest: ((Request) throws -> Void)? = nil,
                    cookie: CookieOptions? = nil,
                    logLevel: Logger.Level = .error) {
            self.pingInterval = pingInterval
            self.pingTimeout = pingTimeout
            self.maxPayload = maxPayload
            self.addTrailingSlash = addTrailingSlash
            self.allowEIO3 = allowEIO3
            self.allowUpgrades = allowUpgrades
            self.allowRequest = allowRequest
            self.cookie = cookie
            self.logLevel = logLevel
        }
    }

    // MARK: Constants

    enum Constant {
        static let okMessage = "ok"
        static let initialPingInterval = 50
        static let softIntervalMultiplier = 2
        static let disallowedMethods: [HTTPMethod] = [.PUT, .DELETE, .PATCH]
    }

    // MARK: Public properties

    public let path: PathComponent
    public let configuration: Configuration

    // MARK: Properties

    var engineClients = [EngineClient]()

    // MARK: Engine

    var connectionHandler: (@Sendable (Client) async -> Void)?
    var disconnectionHandler: (@Sendable (Client, DisconnectReason) async -> Void)?
    var connectionErrorHandler: (@Sendable (Request, Error) async -> Void)?
    var packetsHandler: (@Sendable (Client, [any Packet]) async -> Void)?

    // MARK: Init

    public init(path: PathComponent = "engine.io", configuration: Configuration = .default) {
        self.configuration = configuration
        self.path = path

        Logger.engineLogger.logLevel = configuration.logLevel

        Task { await cleanupTimedOutClients() }
    }
}

// MARK: - RouteCollection

extension DefaultEngine: RouteCollection {
    nonisolated public func boot(routes: Vapor.RoutesBuilder) throws {
        let path: PathComponent = "\(path)\(configuration.addTrailingSlash ? "/" : "")"
        let group = routes.grouped(path)

        group.on(.GET, use: getHandler)
        group.on(.POST, use: postHandler)

        Constant.disallowedMethods.forEach { group.on($0, use: { _ in Response(status: .badRequest) }) }
    }
}

// MARK: - Route handlers

extension DefaultEngine {
    @Sendable private func getHandler(request: Request) async throws -> Response {
        let socketQueryParams = try SocketQueryParams(from: request)

        try checkEngineVersion(queryParams: socketQueryParams)

        if let id = socketQueryParams.id {
            if request.headers.connection == .uprade && configuration.allowUpgrades {
                try await runAllowRequest(request: request)
                return upgradeToWebSocket(id: id, request: request)
            }

            let client = try retreiveClient(for: id)
            let packets = try await pollPackets(for: client)
            return Response(status: .ok, body: .init(stringLiteral: try PacketCoder.encodePackets(packets)))
        }

        try await runAllowRequest(request: request)
        return try openClient(with: socketQueryParams, request: request)
    }

    @Sendable private func postHandler(request: Request) async throws -> Response {
        let socketQueryParams = try SocketQueryParams(from: request)
        let id = try socketQueryParams.getID()

        let client = try retreiveClient(for: id)

        do {
            try await processData(for: client, stringData: request.body.string)
            return Response(status: .ok, body: .init(stringLiteral: Constant.okMessage))
        } catch {
            if case PacketError.invalidPacketFormat = error {
                try handleInvalidPacket(for: client)
            }
            throw error
        }
    }
}

// MARK: - Helpers

extension DefaultEngine {
    private func openClient(with queryParams: SocketQueryParams, request: Request) throws -> Response {
        let transportTypeUpgrades: [TransportType]
        if configuration.allowUpgrades {
            transportTypeUpgrades = TransportType.allCases.filter { $0 < queryParams.transportType }
        } else {
            transportTypeUpgrades = []
        }
        let handshakeResponse = HandshakeResponse(
            transportTypeUpgrades: transportTypeUpgrades,
            configuration: configuration
        )

        switch queryParams.transportType {
        case .polling:
            return try openLongPolling(
                with: handshakeResponse.id,
                handshake: Handshake(from: request),
                handshakeResponse: handshakeResponse
            )
        case .webSocket:
            return openWebsocket(with: handshakeResponse.id, handshakeResponse: handshakeResponse, request: request)
        }
    }

    private func retreiveClient(for id: String) throws -> EngineClient {
        guard let client = getClient(for: id) else { throw Abort(.badRequest) }
        try checkClient(client)
        try checkTimeout(for: client)
        try checkTransportType(for: client)
        return client
    }

    private func checkEngineVersion(queryParams: SocketQueryParams) throws {
        var allowedEngineVersions: [EngineVersion] = [.v4]
        if configuration.allowEIO3 {
            allowedEngineVersions.append(.v3)
        }
        if !allowedEngineVersions.contains(queryParams.engineVersion) {
            throw Abort(.badRequest, reason: "Unsupported engine version")
        }
    }

    private func checkClient(_ client: EngineClient) throws {
        if client.state == .closed {
            defer { removeClient(client, reason: .invalidSession) }
            throw Abort(.badRequest)
        }
    }

    private func runAllowRequest(request: Request) async throws {
        if let allowRequest = configuration.allowRequest {
            try allowRequest(request)
        }
    }

    private func checkTimeout(for client: EngineClient) throws {
        if isClientTimedOut(client) {
            Logger.engineLogger.notice("Client timed out \(client.id)")
            defer { removeClient(client, reason: .pingTimeout) }
            throw Abort(.badRequest)
        }
    }

    private func handleInvalidPacket(for client: EngineClient) throws {
        Logger.engineLogger.notice("Invalid packet from \(client.id)")
        removeClient(client, reason: .invalidPacket)
        throw Abort(.badRequest)
    }

    private func cleanupTimedOutClients() {
        Task.detached(priority: .background) { [unowned self] in
            let softTimedOutInterval = (configuration.pingInterval + configuration.pingTimeout) * Constant.softIntervalMultiplier
            while true {
                for client in await self.engineClients {
                    let difference = Date().timeIntervalSince(client.latestClientReactionTime) * 1000
                    guard Int64(difference) > softTimedOutInterval else { continue }
                    Logger.engineLogger.notice("Client removed by cleanup \(client.id)")
                    await self.removeClient(client, reason: .pingTimeout)
                }
                try? await Task.sleep(milliseconds: softTimedOutInterval)
            }
        }
    }
}
