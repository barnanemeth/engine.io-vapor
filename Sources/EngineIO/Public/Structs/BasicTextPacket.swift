//
//  BasicTextPacket.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Vapor

public struct BasicTextPacket: TextPacket {

    // MARK: Properties

    public let id = UUID()
    public let type: PacketType
    public let payload: String?

    // MARK: Init

    public init(from string: String) throws {
        var text = string
        guard let packetType = PacketType(rawValue: text.removeFirst()) else { throw PacketError.invalidPacketFormat }
        self.type = packetType
        self.payload = text
    }

    public init(with packetType: PacketType, data: String? = nil) {
        self.type = packetType
        self.payload = data
    }

    // MARK: Public methods

    public func rawData() -> String {
        "\(type.rawValue)\(payload ?? "")"
    }
}
