//
//  PacketType.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

public enum PacketType: Character, Sendable {
    case open = "0"
    case close = "1"
    case ping = "2"
    case pong = "3"
    case message = "4"
    case upgrade = "5"
    case noop = "6"
}
