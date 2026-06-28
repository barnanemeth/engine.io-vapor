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
    @DefaultEngine
    func openWebsocket(with id: String, handshakeResponse: HandshakeResponse, request: Request) -> Response {
        request.webSocket { @DefaultEngine [unowned self] _, webSocket async in
            if let client = getClient(for: id), client.transportType == .webSocket {
                logger.info("WebSocket - closing websocket due to existing socket, \(id)")
                try? await webSocket.close()
                return
            }

            let client = self.initClient(
                with: id,
                handshake: Handshake(from: request),
                transportType: .webSocket
            )

            client.webSocket = webSocket
            client.state = .idle
            client.latestClientReactionTime = Date()

            try? await webSocket.send(handshakeResponse.buildBody(with: .open))
            try? await Task.sleep(milliseconds: Constant.initialPingInterval)
            try? await webSocket.send(BasicTextPacket(with: .ping).rawData())

            self.createWebSocketTimer(for: client)

            // Note: temporarily, just try to fix the upgrading
            try? await Task.sleep(milliseconds: 100)
            
            await self.connectionHandler?(client)

            logger.log(level: .info, "WebSocket client connected with ID: \(id)")
        }
    }

    func upgradeToWebSocket(id: String, request: Request) -> Response {
        request.webSocket { @DefaultEngine [unowned self] _, webSocket async in
            guard let client = getClient(for: id) else { return }

            if client.transportType == .webSocket {
                logger.info("WebSocket - closing websocket due to existing socket, \(client.id)")
                try? await webSocket.close()
                return
            }

            logger.info("WebSocket - upgrading started \(client.id)")

            client.webSocket = webSocket
            client.state = .upgrading(state: .waitingForPing)
        }
    }

    @DefaultEngine
    func handlePacketData(for client: EngineClient, packetData: PacketData) async throws {
        client.latestClientReactionTime = Date()
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

    @DefaultEngine
    private func handleTextPacket(for client: EngineClient, packet: any TextPacket) async {
        switch packet.type {
        case .pong:
            handlePongState(for: client)
        case .ping:
            await handlePingState(for: client, packet: packet)
        case .upgrade:
            handleUpgradeState(for: client)
        case .message:
            logger.debug("WebSocket - processing packets for \(client.id)")
            await processPackets(for: client, packets: [packet])
        case .close:
            await closeWebSocketAndRemoveClient(client, reason: .forcefully)
        default:
            return
        }
    }

    @DefaultEngine
    private func handlePongState(for client: EngineClient) {
        guard client.state == .heartbeat(state: .waitingForPong) else { return }
        logger.trace("WebSocket - pong packet received \(client.id)")
        client.latestClientReactionTime = Date()
        client.state = .idle
    }

    @DefaultEngine
    private func handlePingState(for client: EngineClient, packet: any TextPacket) async {
        logger.debug("WebSocket - upgrading - ping probe received \(client.id)")
        client.state = .upgrading(state: .waitingForPing.increased())
        let pongPacket = BasicTextPacket(with: .pong, data: packet.payload as? String)
        try? await client.webSocket?.send(pongPacket.rawData())
    }

    @DefaultEngine
    private func handleUpgradeState(for client: EngineClient) {
        client.transportType = .webSocket
        client.state = .idle
        createWebSocketTimer(for: client)
        logger.info("WebSocket - upgrading successfully finished \(client.id)")
    }

    @DefaultEngine
    private func createWebSocketTimer(for client: EngineClient) {
        let task = Task { @DefaultEngine in
            while true {
                try? await Task.sleep(milliseconds: configuration.pingInterval)
                guard !Task.isCancelled else { return }
                if isClientTimedOut(client) {
                    logger.info("WebSocket - closing client due to timing out \(client.id)")
                    await closeWebSocketAndRemoveClient(client, reason: .pingTimeout)
                    return
                } else if client.state < .upgrading(state: .waitingForPing) {
                    logger.trace("WebSocket - heartbeat - sending ping packet \(client.id)")
                    try? await client.webSocket?.send(BasicTextPacket(with: .ping).rawData())
                    client.state = .heartbeat(state: .waitingForPong)
                }
            }
        }
        client.webSocketTimerTask = task
    }
}
