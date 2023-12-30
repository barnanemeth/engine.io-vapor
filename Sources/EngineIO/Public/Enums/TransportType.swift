//
//  TransportType.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

public enum TransportType: String, Codable, Comparable, Equatable, CaseIterable, Sendable {
    case polling
    case webSocket = "websocket"

    private var priority: UInt8 {
        switch self {
        case .polling: 1 << 7
        case .webSocket: 1 << 8
        }
    }

    public static func < (lhs: TransportType, rhs: TransportType) -> Bool {
        lhs.priority < rhs.priority
    }
}
