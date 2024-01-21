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
            client = EngineClient(id: id, handshake: handshake, transportType: transportType, packetType: packetType)
        } else {
            client = EngineClient(id: id, handshake: handshake, transportType: transportType)
        }
        client.engine = self
        engineClients.append(client)
        return client
    }

    func getClient(for id: String) -> EngineClient? {
        engineClients.first { $0.id == id }
    }

    func removeClient(_ client: EngineClient, reason: DisconnectReason) {
        guard let index = engineClients.firstIndex(of: client) else { return }
        Task { await disconnectionHandler?(client, reason) }
        client.pendingPollTask = nil
        client.webSocketTimerTask = nil
        client.changeChannel.finish()
        engineClients.remove(at: index)
        Logger.engineLogger.info("Client disconnected \(client.id)")
    }

    func closeWebSocketAndRemoveClient(_ client: EngineClient, reason: DisconnectReason) async {
        try? await client.webSocket?.close()
        removeClient(client, reason: reason)
    }

    func isClientTimedOut(_ client: EngineClient) -> Bool {
        var threshold = Double(configuration.pingInterval + configuration.pingTimeout)
        if case .upgrading = client.state {
            threshold *= Constant.upgradeTimeoutThresholdMultiplier
        }
        return Date().timeIntervalSince(client.latestClientReactionTime) * 1000 > threshold
    }

    func checkTransportType(for client: EngineClient) throws {
        if client.transportType == .webSocket {
            Logger.engineLogger.notice("Polling declined \(client.id)")
            throw Abort(.badRequest)
        }
    }

    func processPackets(for client: EngineClient, packets: [any Packet]) async {
        client.state = .idle
        await packetsHandler?(client, packets)
    }

    func sendPackets(for client: EngineClient, packets: [any Packet]) async {
        Logger.engineLogger.debug("Sending packets for \(client.id), packet count: \(packets.count)")
        switch client.transportType {
        case .polling:
            client.packetBuffer.append(contentsOf: packets)
        case .webSocket:
            guard let webSocket = client.webSocket else { return }
            defer { client.packetBuffer.removeAll() }
            for packet in packets {
                switch packet {
                case let textPacket as (any TextPacket): try? await webSocket.send(textPacket.rawData())
                case let binaryPacket as BinaryPacket: webSocket.send(binaryPacket.rawData())
                default: Logger.engineLogger.notice("Invalid packet type, \(client.id)")
                }
            }
        }
    }

    func disconnectClient(_ client: Client) async {
        guard let client = client as? EngineClient else { return }
        await closeWebSocketAndRemoveClient(client, reason: .forcefully)
    }
}
