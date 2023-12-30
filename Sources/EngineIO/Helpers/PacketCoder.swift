//
//  PacketCoder.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

enum PacketCoder {

    // MARK: Constants

    private enum Constant {
        static let separator = "\u{1e}"
    }

    // MARK: Public methods

    static func decodePacket(from byteBuffer: ByteBuffer) -> BinaryPacket {
        BinaryPacket(byteBuffer: byteBuffer)
    }

    static func decodePacket(from data: String?) throws -> any Packet {
        guard let data else { throw PacketError.invalidPacketFormat }
        if let data = Data(base32Encoded: data) {
            return BinaryPacket(byteBuffer: ByteBuffer(data: data))
        }
        return try BasicTextPacket(from: data)
    }

    static func decodePackets(from data: String?, maxPayload: Int) throws -> [any Packet] {
        guard let data else { throw PacketError.invalidPacketFormat }
        let packets = try data.components(separatedBy: Constant.separator).map { try decodePacket(from: $0) }
        guard packets.count < maxPayload else { throw PacketError.tooLargePacketSequence }
        return packets
    }

    static func encodePackets(_ packets: [any Packet]) throws -> String {
        try packets.compactMap { packet -> String? in
            switch packet {
            case let textPacket as (any TextPacket):
                return textPacket.rawData()
            case let binaryPacket as BinaryPacket:
                return "b\(binaryPacket.base64String ?? "")"
            default:
                Logger.engineLogger.warning("Packet encoding - invalid packet type")
                throw PacketError.invalidPacketType
            }
        }.joined(separator: Constant.separator)
    }
}
