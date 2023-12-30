//
//  ClientState.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

enum ClientState: Equatable, Comparable, Hashable {
    case opening
    case idle
    case heartbeat(state: HeartbeatState)
    case upgrading(state: UpgradingState)
    case closed

    var orderValue: Int {
        switch self {
        case .opening: return 1
        case .idle, .heartbeat: return 2
        case .upgrading: return 3
        case .closed: return 0
        }
    }

    static func == (lhs: ClientState, rhs: ClientState) -> Bool {
        lhs.orderValue == rhs.orderValue
    }

    static func < (lhs: ClientState, rhs: ClientState) -> Bool {
        lhs.orderValue < rhs.orderValue
    }
}
