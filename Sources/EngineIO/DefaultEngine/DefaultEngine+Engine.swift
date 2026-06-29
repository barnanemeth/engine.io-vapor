//
//  DefaultEngine+Engine.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

// MARK: - Engine

extension DefaultEngine: Engine {
    public var clients: [Client] { engineClients }

    public func onPackets(use closure: @escaping @Sendable (Client, [any Packet]) async -> Void) {
        packetsHandler = closure
    }

    public func onConnection(use closure: @escaping @Sendable (Client) async -> Void) {
        connectionHandler = closure
    }

    public func onDisconnection(use closure: @Sendable @escaping (Client, DisconnectReason) async -> Void) {
        disconnectionHandler = closure
    }

    public func onConnectionError(use closure: @escaping @Sendable (Request, Error) async -> Void) {
        connectionErrorHandler = closure
    }
}
