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
    @DefaultEngine
    func openLongPolling(with id: String, handshake: Handshake, handshakeResponse: HandshakeResponse ) throws -> Response {
        let client = initClient(with: id, handshake: handshake, transportType: .polling, packetType: .open)
        defer {
            client.state = .idle
            client.packetBuffer.removeAll()
            logger.log(level: .info, "Polling client connected with ID: \(client.id)")
            Task {
                // Note: temporarily, just try to fix the upgrading
                try? await Task.sleep(milliseconds: 100)
                await connectionHandler?(client)
            }
        }
        let resonse = Response(status: .ok, body: Response.Body(stringLiteral: try handshakeResponse.buildBody(with: .open)))
        setCookieIfNeeded(for: resonse)
        return resonse
    }

    @DefaultEngine
    func processData(for client: EngineClient, stringData: String?) async throws {
        client.latestClientReactionTime = Date()
        let packets = try PacketCoder.decodePackets(from: stringData, maxPayload: configuration.maxPayload)
        for packet in packets {
            switch packet {
            case let textPacket as BasicTextPacket:
                switch textPacket.type {
                case .ping:
                    logger.trace("Polling - heartbeat - ping packet received for \(client.id)")
                    client.state = .heartbeat(state: .sendingPing)
                case .pong:
                    guard client.state == .heartbeat(state: .waitingForPong) else { break }
                    logger.trace("Polling - heartbeat - pong packet received \(client.id)")
                    client.state = .idle
                case .close:
                    logger.debug("Polling - force closing for \(client.id)")
                    await handleClosing(for: client)
                case .message:
                    logger.debug("Polling - processing packets for \(client.id), packet count: \(packets.count)")
                    await processPackets(for: client, packets: [textPacket])
                default:
                    break
                }
            case let binaryPacket as BinaryPacket:
                await processPackets(for: client, packets: [binaryPacket])
            default:
                break
            }
        }
    }

    @DefaultEngine
    func pollPackets(for client: EngineClient) async throws -> [any Packet] {
        let task = Task {
            let pollTimeoutTask = createPollTimeoutTimer(for: client)

            defer { resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask) }

            for await _ in client.changeChannel {
                switch client.state {
                case .closed:
                    return await [handleClosedPollingState(for: client)]
                case let .heartbeat(state):
                    return [handleHeartbeatPollingState(with: state, client: client)]
                case .idle:
                    guard !client.packetBuffer.isEmpty else { break }
                    return client.packetBuffer
                case .upgrading:
                    return [BasicTextPacket(with: .noop)]
                default:
                    break
                }
            }

            return [BasicTextPacket(with: .close)]
        }
        try await checkPollConditions(for: client)
        client.pendingPollTask = task
        return await task.value
    }

    @DefaultEngine
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
        Task { @DefaultEngine in
            logger.debug("Polling - closing client \(client.id)")
            client.state = .closed
            let delay = configuration.pingInterval + configuration.pingTimeout
            try? await Task.sleep(milliseconds: delay)
            await removeClient(client, reason: .forcefully)
        }
    }

    @DefaultEngine
    private func handleClosedPollingState(for client: EngineClient) async -> any Packet {
        await removeClient(client, reason: .forcefully)
        return BasicTextPacket(with: .noop)
    }

    @DefaultEngine
    private func handleHeartbeatPollingState(with heartbeatState: HeartbeatState, client: EngineClient) -> any Packet {
        switch heartbeatState {
        case .sendingPing:
            logger.trace("Polling - heartbeat - sending ping packet for \(client.id)")
            defer { client.state = .heartbeat(state: .waitingForPong) }
            return BasicTextPacket(with: .ping)
        case .sendingPong:
            logger.trace("Polling - heartbeat - sending pong packet for \(client.id)")
            return BasicTextPacket(with: .pong)
        case .waitingForPong:
            return BasicTextPacket(with: .pong) // TODO
        }
    }

    @DefaultEngine
    private func checkPollConditions(for client: EngineClient) async throws {
        try await checkPendingPolling(for: client)
        try checkTransportType(for: client)
    }

    @DefaultEngine
    private func checkPendingPolling(for client: EngineClient) async throws {
        guard let task = client.pendingPollTask else { return }
        logger.info("Polling - closing client due to duplicated poll requests, \(client.id)")
        client.state = .closed
        task.cancel()
        await removeClient(client, reason: .invalidState)
        throw Abort(.badRequest)
    }

    @DefaultEngine
    private func resetTransferringState(for client: EngineClient, pollTimeoutTask: Task<Void, Never>) {
        pollTimeoutTask.cancel()
        client.packetBuffer.removeAll()
        client.state = .idle
        client.pendingPollTask = nil
    }

    @DefaultEngine
    private func createPollTimeoutTimer(for client: EngineClient) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(milliseconds: configuration.pingInterval)
            guard !Task.isCancelled, client.state > .closed else { return }
            client.state = .heartbeat(state: .sendingPing)
        }
    }
}
