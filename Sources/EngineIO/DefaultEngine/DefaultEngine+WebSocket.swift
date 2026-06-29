//
//  DefaultEngine+WebSocket.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

// MARK: - WebSocket

extension DefaultEngine {
    func openWebsocket(with id: String, handshakeResponse: HandshakeResponse, request: Request) -> Response {
        request.webSocket { [unowned self] _, webSocket async in
            if let client = await getClient(for: id), await client.transportTypeSnapshot() == .webSocket {
                logger.info("WebSocket - closing websocket due to existing socket, \(id)")
                try? await webSocket.close()
                return
            }

            let client = await initClient(
                with: id,
                handshake: Handshake(from: request),
                transportType: .webSocket
            )

            await client.setWebSocket(webSocket)
            await client.setState(.idle)
            await client.updateLatestClientReactionTime()

            try? await webSocket.send(handshakeResponse.buildBody(with: .open))
            try? await Task.sleep(milliseconds: Constant.initialPingInterval)
            try? await webSocket.send(BasicTextPacket(with: .ping).rawData())

            await self.createWebSocketTimer(for: client)

            // Note: temporarily, just try to fix the upgrading
            try? await Task.sleep(milliseconds: 100)
            
            await self.connectionHandler?(client)

            logger.log(level: .info, "WebSocket client connected with ID: \(id)")
        }
    }

    func upgradeToWebSocket(id: String, request: Request) -> Response {
        request.webSocket { [unowned self] _, webSocket async in
            guard let client = await getClient(for: id) else { return }

            if await client.transportTypeSnapshot() == .webSocket {
                logger.info("WebSocket - closing websocket due to existing socket, \(client.id)")
                try? await webSocket.close()
                return
            }

            logger.info("WebSocket - upgrading started \(client.id)")

            await client.setWebSocket(webSocket)
            await client.setState(.upgrading(state: .waitingForPing))
        }
    }

    func handlePacketData(for client: EngineClient, packetData: PacketData) async throws {
        await client.updateLatestClientReactionTime()
        do {
            switch packetData {
            case let .binary(byteBuffer):
                let packet = PacketCoder.decodePacket(from: byteBuffer)
                logger.debug("WebSocket - processing binary packet \(client.id)")
                await processPackets(for: client, packets: [packet])
            case let .text(string):
                guard let packet = try PacketCoder.decodePacket(from: string) as? (any TextPacket) else { return }
                await handleTextPacket(for: client, packet: packet)
            }

        } catch {
            if case PacketError.invalidPacketFormat = error {
                logger.info("WebSocket - closing client due to invalid packet format \(client.id)")
                await closeWebSocketAndRemoveClient(client, reason: .invalidPacket)
            }
            throw error
        }
    }

    private func handleTextPacket(for client: EngineClient, packet: any TextPacket) async {
        switch packet.type {
        case .pong:
            await handlePongState(for: client)
        case .ping:
            await handlePingState(for: client, packet: packet)
        case .upgrade:
            await handleUpgradeState(for: client)
        case .message:
            logger.debug("WebSocket - processing packets for \(client.id)")
            await processPackets(for: client, packets: [packet])
        case .close:
            await closeWebSocketAndRemoveClient(client, reason: .forcefully)
        default:
            return
        }
    }

    private func handlePongState(for client: EngineClient) async {
        guard await client.stateSnapshot() == .heartbeat(state: .waitingForPong) else { return }
        logger.trace("WebSocket - pong packet received \(client.id)")
        await client.updateLatestClientReactionTime()
        await client.setState(.idle)
    }

    private func handlePingState(for client: EngineClient, packet: any TextPacket) async {
        logger.debug("WebSocket - upgrading - ping probe received \(client.id)")
        await client.setState(.upgrading(state: .waitingForPing.increased()))
        let pongPacket = BasicTextPacket(with: .pong, data: packet.payload as? String)
        try? await client.webSocketSnapshot()?.send(pongPacket.rawData())
    }

    private func handleUpgradeState(for client: EngineClient) async {
        await client.setTransportType(.webSocket)
        await client.setState(.idle)
        await createWebSocketTimer(for: client)
        logger.info("WebSocket - upgrading successfully finished \(client.id)")
    }

    private func createWebSocketTimer(for client: EngineClient) async {
        let task = Task {
            while true {
                try? await Task.sleep(milliseconds: configuration.pingInterval)
                guard !Task.isCancelled else { return }
                if await isClientTimedOut(client) {
                    logger.info("WebSocket - closing client due to timing out \(client.id)")
                    await closeWebSocketAndRemoveClient(client, reason: .pingTimeout)
                    return
                } else if await client.stateSnapshot() < .upgrading(state: .waitingForPing) {
                    logger.trace("WebSocket - heartbeat - sending ping packet \(client.id)")
                    try? await client.webSocketSnapshot()?.send(BasicTextPacket(with: .ping).rawData())
                    await client.setState(.heartbeat(state: .waitingForPong))
                }
            }
        }
        await client.setWebSocketTimerTask(task)
    }
}
