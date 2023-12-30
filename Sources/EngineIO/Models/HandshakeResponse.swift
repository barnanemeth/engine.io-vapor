//
//  HandshakeResponse.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

struct HandshakeResponse {

    // MARK: CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id = "sid"
        case transportTypeUpgrades = "upgrades"
        case pingInterval
        case pingTimeout
        case maxPayload
    }

    // MARK: Properties

    let id: String
    let transportTypeUpgrades: [TransportType]
    let pingInterval: Int
    let pingTimeout: Int
    let maxPayload: Int

    // MARK: Init

    init(id: String = UUID().uuidString,
         transportTypeUpgrades: [TransportType],
         configuration: DefaultEngine.Configuration
    ) {
        self.id = id
        self.transportTypeUpgrades = transportTypeUpgrades
        self.pingInterval = configuration.pingInterval
        self.pingTimeout = configuration.pingTimeout
        self.maxPayload = configuration.maxPayload
    }

    // MARK: Public methods

    func buildBody(with packetType: PacketType) throws -> String {
        let handshakeData = try JSONEncoder().encode(self)
        let handshakeString = String(data: handshakeData, encoding: .utf8) ?? ""
        return "\(packetType.rawValue)\(handshakeString)"
    }
}

// MARK: - Content

extension HandshakeResponse: Content {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.transportTypeUpgrades = try container.decode([TransportType].self, forKey: .transportTypeUpgrades)
        self.pingInterval = try container.decode(Int.self, forKey: .pingInterval)
        self.pingTimeout = try container.decode(Int.self, forKey: .pingTimeout)
        self.maxPayload = try container.decode(Int.self, forKey: .maxPayload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(transportTypeUpgrades, forKey: .transportTypeUpgrades)
        try container.encode(pingInterval, forKey: .pingInterval)
        try container.encode(pingTimeout, forKey: .pingTimeout)
        try container.encode(maxPayload, forKey: .maxPayload)
    }
}
