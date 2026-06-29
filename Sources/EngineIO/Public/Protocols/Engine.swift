//
//  Engine.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public protocol Engine: RouteCollection, Actor {
    var clients: [Client] { get }

    func onConnection(use closure: @Sendable @escaping (Client) async -> Void)
    func onDisconnection(use closure: @Sendable @escaping (Client, DisconnectReason) async -> Void)
    func onConnectionError(use closure: @Sendable @escaping (Request, Error) async -> Void)
    func onPackets(use closure: @Sendable @escaping (Client, [any Packet]) async -> Void)
}
