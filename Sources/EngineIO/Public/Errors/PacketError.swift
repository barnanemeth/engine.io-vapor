//
//  PacketError.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

public enum PacketError: Error {
    case invalidPacketFormat
    case tooLargePacketSequence
    case invalidPacketType
}

