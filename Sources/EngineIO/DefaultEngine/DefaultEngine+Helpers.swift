//
//  DefaultEngine+Helpers.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

// MARK: - Helpers

extension DefaultEngine {
    @discardableResult func initClient(
        with id: String,
        handshake: Handshake,
        transportType: TransportType,
        packetType: PacketType? = nil
    ) -> EngineClient {
        let client: EngineClient
        if let packetType {
            client = EngineClient(id: id, handshake: handshake, transportType: transportType, engine: self, packetType: packetType)
        } else {
            client = EngineClient(id: id, handshake: handshake, transportType: transportType, engine: self)
        }
        engineClients.append(client)
        return client
    }

    func getClient(for id: String) -> EngineClient? {
        engineClients.first { $0.id == id }
    }

    func removeClient(_ client: EngineClient, reason: DisconnectReason) async {
        guard let index = engineClients.firstIndex(where: { $0.id == client.id }) else { return }
        await disconnectionHandler?(client, reason)
        await client.finish()
        engineClients.remove(at: index)
        logger.info("Client disconnected \(client.id)")
    }

    func closeWebSocketAndRemoveClient(_ client: EngineClient, reason: DisconnectReason) async {
        try? await client.webSocketSnapshot()?.close()
        await removeClient(client, reason: reason)
    }

    func isClientTimedOut(_ client: EngineClient) async -> Bool {
        var threshold = Double(configuration.pingInterval + configuration.pingTimeout)
        if case .upgrading = await client.stateSnapshot() {
            threshold *= Constant.upgradeTimeoutThresholdMultiplier
        }
        let latestClientReactionTime = await client.latestClientReactionTimeSnapshot()
        return Date().timeIntervalSince(latestClientReactionTime) * 1000 > threshold
    }

    func checkTransportType(for client: EngineClient) async throws {
        if await client.transportTypeSnapshot() == .webSocket {
            logger.notice("Polling declined \(client.id)")
            throw Abort(.badRequest)
        }
    }

    func processPackets(for client: EngineClient, packets: [any Packet]) async {
        await client.setState(.idle)
        await packetsHandler?(client, packets)
    }

    func sendPackets(for client: EngineClient, packets: [any Packet]) async {
        logger.debug("Sending packets for \(client.id), packet count: \(packets.count)")
        await client.appendPacketsToBuffer(packets)
        if let webSocket = await client.webSocketSnapshot() {
            for packet in packets {
                switch packet {
                case let textPacket as (any TextPacket): try? await webSocket.send(textPacket.rawData())
                case let binaryPacket as BinaryPacket: webSocket.send(binaryPacket.rawData())
                default: logger.notice("Invalid packet type, \(client.id)")
                }
            }
            await client.clearPacketBuffer()
        }
    }

    func disconnectClient(_ client: Client) async {
        guard let client = client as? EngineClient else { return }
        await closeWebSocketAndRemoveClient(client, reason: .forcefully)
    }
}
