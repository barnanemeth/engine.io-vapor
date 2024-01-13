//
//  DisconnectReason.swift
//
//
//  Created by Barna Nemeth on 13/01/2024.
//

import Foundation

public enum DisconnectReason {
    case pingTimeout
    case forcefully
    case invalidPacket
    case invalidSession
    case invalidState
}
