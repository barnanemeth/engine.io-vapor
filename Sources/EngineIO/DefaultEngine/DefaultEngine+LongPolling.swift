//
//  DefaultEngine+LongPolling.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

// MARK: - HTTP Long Polling

extension DefaultEngine {
    func openLongPolling(with id: String, handshake: Handshake, handshakeResponse: HandshakeResponse ) throws -> Response {
        let client = initClient(with: id, handshake: handshake, transportType: .polling, packetType: .open)
        defer {
            client.state = .idle
            client.packetBuffer.removeAll()
            Logger.engineLogger.log(level: .info, "Polling client connected with ID: \(client.id)")
            Task { await connectionHandler?(client) }
        }
        let resonse = Response(status: .ok, body: Response.Body(stringLiteral: try handshakeResponse.buildBody(with: .open)))
        setCookieIfNeeded(for: resonse)
        return resonse
    }

    func processData(for client: EngineClient, stringData: String?) async throws {
        client.latestClientReactionTime = Date()
        let packets = try PacketCoder.decodePackets(from: stringData, maxPayload: configuration.maxPayload)
        for packet in packets {
            switch packet {
            case let textPacket as BasicTextPacket:
                if textPacket.type == .ping {
                    Logger.engineLogger.trace("Polling - heartbeat - ping packet received for \(client.id)")
                    client.state = .heartbeat(state: .sendingPing)
                } else if textPacket.type == .pong && client.state == .heartbeat(state: .waitingForPong) {
                    Logger.engineLogger.trace("Polling - heartbeat - pong packet received \(client.id)")
                    client.state = .idle
                } else if textPacket.type == .close {
                    Logger.engineLogger.debug("Polling - force closing for \(client.id)")
                    handleClosing(for: client)
                } else if textPacket.type == .message {
                    Logger.engineLogger.debug("Polling - processing packets for \(client.id), packet count: \(packets.count)")
                    await processPackets(for: client, packets: [textPacket])
                }
            case let binaryPacket as BinaryPacket:
                await processPackets(for: client, packets: [binaryPacket])
            default:
                break
            }
        }
    }

    func pollPackets(for client: EngineClient) async throws -> [any Packet] {
        let task = Task {
            let pollTimeoutTask = createPollTimeoutTimer(for: client)

            defer { resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask) }

            for await _ in client.changeChannel {
                switch client.state {
                case .closed:
                    return [handleClosedPollingState(for: client)]
                case let .heartbeat(state):
                    return [handleHeartbeatPollingState(with: state, client: client)]
                case .idle:
                    guard !client.packetBuffer.isEmpty else { break }
                    return client.packetBuffer
                case .upgrading(.sendingPong):
                    return [BasicTextPacket(with: .noop)]
                default:
                    break
                }
            }

            return [BasicTextPacket(with: .close)]
        }
        try checkPollConditions(for: client)
        client.pendingPollTask = task
        return await task.value
    }

    private func setCookieIfNeeded(for response: Response) {
        guard let cookieOptions = configuration.cookie else { return }
        response.cookies[cookieOptions.name] = HTTPCookies.Value(
            string: UUID().uuidString,
            expires: cookieOptions.expires,
            maxAge: cookieOptions.maxAge,
            domain: cookieOptions.domain,
            path: cookieOptions.path,
            isSecure: cookieOptions.isSecure,
            isHTTPOnly: cookieOptions.isHTTPOnly,
            sameSite: cookieOptions.sameSite
        )
    }

    private func handleClosing(for client: EngineClient) {
        Task {
            Logger.engineLogger.debug("Polling - closing client \(client.id)")
            client.state = .closed
            let delay = configuration.pingInterval + configuration.pingTimeout
            try? await Task.sleep(milliseconds: delay)
            removeClient(client)
        }
    }

    private func handleClosedPollingState(for client: EngineClient) -> any Packet {
        defer { removeClient(client) }
        return BasicTextPacket(with: .noop)
    }

    private func handleHeartbeatPollingState(with heartbeatState: HeartbeatState, client: EngineClient) -> any Packet {
        switch heartbeatState {
        case .sendingPing:
            Logger.engineLogger.trace("Polling - heartbeat - sending ping packet for \(client.id)")
            defer { client.state = .heartbeat(state: .waitingForPong) }
            return BasicTextPacket(with: .ping)
        case .sendingPong:
            Logger.engineLogger.trace("Polling - heartbeat - sending pong packet for \(client.id)")
            return BasicTextPacket(with: .pong)
        case .waitingForPong:
            return BasicTextPacket(with: .pong) // TODO
        }
    }

    private func checkPollConditions(for client: EngineClient) throws {
        try checkPendingPolling(for: client)
        try checkTransportType(for: client)
    }

    private func checkPendingPolling(for client: EngineClient) throws {
        guard let task = client.pendingPollTask else { return }
        Logger.engineLogger.info("Polling - closing client due to duplicated poll requests, \(client.id)")
        defer { removeClient(client) }
        client.state = .closed
        task.cancel()
        throw Abort(.badRequest)
    }

    private func resetTransferringState(for client: EngineClient, pollTimeoutTask: Task<Void, Never>) {
        pollTimeoutTask.cancel()
        client.packetBuffer.removeAll()
        client.state = .idle
        client.pendingPollTask = nil
    }

    private func createPollTimeoutTimer(for client: EngineClient) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(milliseconds: configuration.pingInterval)
            guard !Task.isCancelled, client.state > .closed else { return }
            client.state = .heartbeat(state: .sendingPing)
        }
    }
}
