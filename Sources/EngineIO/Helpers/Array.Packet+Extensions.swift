//
//  Array.Packet+Extensions.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

extension Array where Element == any Packet {
    var textPackets: [any TextPacket] {
        compactMap { $0 as? (any TextPacket) }
    }

    func hasPacket(of type: PacketType) -> Bool {
        textPackets.contains(where: { $0.type == type })
    }

    func getPacket(for type: PacketType) -> (any TextPacket)? {
        textPackets.first(where: { $0.type == type })
    }
}
