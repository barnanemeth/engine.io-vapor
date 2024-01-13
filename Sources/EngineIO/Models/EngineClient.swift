//
//  EngineClient.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor
import AsyncAlgorithms

final class EngineClient {

    // MARK: Properties

    let id: String
    let connectionTime = Date()
    let handshake: Handshake
    var transportType: TransportType
    var latestClientReactionTime = Date()
    weak var webSocket: WebSocket? { didSet { setWebSocketHandlersIfPossible() } }
    weak var engine: DefaultEngine?

    var pendingPollTask: Task<[any Packet], Never>? {
        willSet { pendingPollTask?.cancel() }
    }
    var webSocketTimerTask: Task<Void, Never>? {
        willSet { webSocketTimerTask?.cancel() }
    }

    var state: ClientState { willSet { triggerChange() }}
    var packetBuffer: [any Packet] { willSet { triggerChange() } }

    var changeChannel = AsyncChannel<Void>()

    // MARK: Init

    init(id: String, handshake: Handshake, transportType: TransportType, packetType: PacketType? = nil) {
        self.id = id
        self.handshake = handshake
        self.transportType = transportType
        self.state = .opening
        if let packetType {
            self.packetBuffer = [BasicTextPacket(with: packetType)]
        } else {
            self.packetBuffer = []
        }
    }
}

// MARK: - Equatable

extension EngineClient: Equatable, Hashable {
    static func == (lhs: EngineClient, rhs: EngineClient) -> Bool {
        lhs.id == rhs.id &&
        lhs.transportType == rhs.transportType &&
        lhs.state == rhs.state &&
        lhs.packetBuffer.map { $0.id } == rhs.packetBuffer.map { $0.id }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(transportType)
        hasher.combine(state)
        hasher.combine(packetBuffer.count)
    }
}

// MARK: - Client

extension EngineClient: Client {
    func sendPackets(_ packets: [any Packet]) async {
        await engine?.sendPackets(for: self, packets: packets)
    }

    func sendPacket(_ packet: any Packet) async {
        await engine?.sendPackets(for: self, packets: [packet])
    }

    func disconnect() async {
        await engine?.disconnectClient(self)
    }
}

// MARK: - Helpers

extension EngineClient {
    private func setWebSocketHandlersIfPossible() {
        guard let webSocket else { return }
        webSocket.onText { [weak self] webSocket, text async in
            guard let self else { return }
            try? await engine?.handlePacketData(for: self, packetData: .text(text))
        }
        webSocket.onBinary { [weak self] webSocket, byteBuffer async in
            guard let self else { return }
            try? await engine?.handlePacketData(for: self, packetData: .binary(byteBuffer))
        }
        Task {
            try? await webSocket.onClose.get()
            await engine?.closeWebSocketAndRemoveClient(self, reason: .forcefully)
        }
    }

    private func triggerChange() {
        Task { await changeChannel.send(()) }
    }
}

