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
    func openLongPolling(with id: String, handshake: Handshake, handshakeResponse: HandshakeResponse ) async throws -> Response {
        let client = initClient(with: id, handshake: handshake, transportType: .polling, packetType: .open)
        let resonse = Response(status: .ok, body: Response.Body(stringLiteral: try handshakeResponse.buildBody(with: .open)))
        setCookieIfNeeded(for: resonse)

        await client.setState(.idle)
        await client.clearPacketBuffer()
        logger.log(level: .info, "Polling client connected with ID: \(client.id)")
        Task {
            // Note: temporarily, just try to fix the upgrading
            try? await Task.sleep(milliseconds: 100)
            await connectionHandler?(client)
        }

        return resonse
    }

    func processData(for client: EngineClient, stringData: String?) async throws {
        await client.updateLatestClientReactionTime()
        let packets = try PacketCoder.decodePackets(from: stringData, maxPayload: configuration.maxPayload)
        for packet in packets {
            switch packet {
            case let textPacket as BasicTextPacket:
                switch textPacket.type {
                case .ping:
                    logger.trace("Polling - heartbeat - ping packet received for \(client.id)")
                    await client.setState(.heartbeat(state: .sendingPing))
                case .pong:
                    guard await client.stateSnapshot() == .heartbeat(state: .waitingForPong) else { break }
                    logger.trace("Polling - heartbeat - pong packet received \(client.id)")
                    await client.setState(.idle)
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

    func pollPackets(for client: EngineClient) async throws -> [any Packet] {
        let task = Task { () -> [any Packet] in
            let pollTimeoutTask = createPollTimeoutTimer(for: client)

            for await _ in client.changeChannel {
                switch await client.stateSnapshot() {
                case .closed:
                    let packets = await [handleClosedPollingState(for: client)]
                    await resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask)
                    return packets
                case let .heartbeat(state):
                    let packets = await [handleHeartbeatPollingState(with: state, client: client)]
                    await resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask)
                    return packets
                case .idle:
                    guard await !client.isPacketBufferEmpty() else { break }
                    let packets = await client.packetBufferSnapshot()
                    await resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask)
                    return packets
                case .upgrading:
                    await resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask)
                    return [BasicTextPacket(with: .noop)]
                default:
                    break
                }
            }

            await resetTransferringState(for: client, pollTimeoutTask: pollTimeoutTask)
            return [BasicTextPacket(with: .close)]
        }
        try await checkPollConditions(for: client)
        await client.setPendingPollTask(task)
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

    private func handleClosing(for client: EngineClient) async {
        logger.debug("Polling - closing client \(client.id)")
        await client.setState(.closed)
        let delay = configuration.pingInterval + configuration.pingTimeout
        try? await Task.sleep(milliseconds: delay)
        await removeClient(client, reason: .forcefully)
    }

    private func handleClosedPollingState(for client: EngineClient) async -> any Packet {
        await removeClient(client, reason: .forcefully)
        return BasicTextPacket(with: .noop)
    }

    private func handleHeartbeatPollingState(with heartbeatState: HeartbeatState, client: EngineClient) async -> any Packet {
        switch heartbeatState {
        case .sendingPing:
            logger.trace("Polling - heartbeat - sending ping packet for \(client.id)")
            await client.setState(.heartbeat(state: .waitingForPong))
            return BasicTextPacket(with: .ping)
        case .sendingPong:
            logger.trace("Polling - heartbeat - sending pong packet for \(client.id)")
            return BasicTextPacket(with: .pong)
        case .waitingForPong:
            return BasicTextPacket(with: .pong) // TODO
        }
    }

    private func checkPollConditions(for client: EngineClient) async throws {
        try await checkPendingPolling(for: client)
        try await checkTransportType(for: client)
    }

    private func checkPendingPolling(for client: EngineClient) async throws {
        guard let task = await client.pendingPollTaskSnapshot() else { return }
        logger.info("Polling - closing client due to duplicated poll requests, \(client.id)")
        await client.setState(.closed)
        task.cancel()
        await removeClient(client, reason: .invalidState)
        throw Abort(.badRequest)
    }

    private func resetTransferringState(for client: EngineClient, pollTimeoutTask: Task<Void, Never>) async {
        pollTimeoutTask.cancel()
        await client.clearPacketBuffer()
        await client.setState(.idle)
        await client.setPendingPollTask(nil)
    }

    private func createPollTimeoutTimer(for client: EngineClient) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(milliseconds: configuration.pingInterval)
            guard !Task.isCancelled, await client.stateSnapshot() > .closed else { return }
            await client.setState(.heartbeat(state: .sendingPing))
        }
    }
}
