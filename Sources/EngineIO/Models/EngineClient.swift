//
//  EngineClient.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor
import AsyncAlgorithms

actor EngineClient {

    // MARK: Properties

    nonisolated let id: String
    nonisolated let connectionTime = Date()
    nonisolated let handshake: Handshake
    nonisolated let changeChannel = AsyncChannel<Void>()

    var transportType: TransportType

    // MARK: Private properties

    private var latestClientReactionTime = Date()
    private weak var webSocket: WebSocket?
    private weak var engine: DefaultEngine?
    private var pendingPollTask: Task<[any Packet], Never>? {
        willSet { pendingPollTask?.cancel() }
    }
    private var webSocketTimerTask: Task<Void, Never>? {
        willSet { webSocketTimerTask?.cancel() }
    }
    private var state: ClientState
    private var packetBuffer: [any Packet]

    // MARK: Init

    init(
        id: String,
        handshake: Handshake,
        transportType: TransportType,
        engine: DefaultEngine,
        packetType: PacketType? = nil
    ) {
        self.id = id
        self.handshake = handshake
        self.transportType = transportType
        self.engine = engine
        self.state = .opening
        if let packetType {
            self.packetBuffer = [BasicTextPacket(with: packetType)]
        } else {
            self.packetBuffer = []
        }
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

// MARK: - State helpers

extension EngineClient {
    func setTransportType(_ transportType: TransportType) {
        self.transportType = transportType
    }

    func transportTypeSnapshot() -> TransportType {
        transportType
    }

    func updateLatestClientReactionTime() {
        latestClientReactionTime = Date()
    }

    func latestClientReactionTimeSnapshot() -> Date {
        latestClientReactionTime
    }

    func setWebSocket(_ webSocket: WebSocket?) {
        self.webSocket = webSocket
        setWebSocketHandlersIfPossible()
    }

    func webSocketSnapshot() -> WebSocket? {
        webSocket
    }

    func setPendingPollTask(_ task: Task<[any Packet], Never>?) {
        pendingPollTask = task
    }

    func pendingPollTaskSnapshot() -> Task<[any Packet], Never>? {
        pendingPollTask
    }

    func setWebSocketTimerTask(_ task: Task<Void, Never>?) {
        webSocketTimerTask = task
    }

    func setState(_ state: ClientState) {
        self.state = state
        triggerChange()
    }

    func stateSnapshot() -> ClientState {
        state
    }

    func appendPacketsToBuffer(_ packets: [any Packet]) {
        packetBuffer.append(contentsOf: packets)
        triggerChange()
    }

    func clearPacketBuffer() {
        packetBuffer.removeAll()
        triggerChange()
    }

    func isPacketBufferEmpty() -> Bool {
        packetBuffer.isEmpty
    }

    func packetBufferSnapshot() -> [any Packet] {
        packetBuffer
    }

    func finish() {
        pendingPollTask = nil
        webSocketTimerTask = nil
        changeChannel.finish()
    }
}

// MARK: - Helpers

extension EngineClient {
    private func setWebSocketHandlersIfPossible() {
        guard let webSocket else { return }
        webSocket.onText { [weak self] _, text async in
            guard let self else { return }
            await self.handlePacketData(.text(text))
        }
        webSocket.onBinary { [weak self] _, byteBuffer async in
            guard let self else { return }
            await self.handlePacketData(.binary(byteBuffer))
        }
        Task { [weak self] in
            try? await webSocket.onClose.get()
            guard let self else { return }
            await self.close(reason: .forcefully)
        }
    }

    private func handlePacketData(_ packetData: PacketData) async {
        try? await engine?.handlePacketData(for: self, packetData: packetData)
    }

    private func close(reason: DisconnectReason) async {
        await engine?.closeWebSocketAndRemoveClient(self, reason: reason)
    }

    private func triggerChange() {
        Task { await changeChannel.send(()) }
    }
}
