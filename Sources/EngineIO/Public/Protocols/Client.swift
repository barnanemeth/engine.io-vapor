//
//  Client.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

public protocol Client {
    var id: String { get }
    var connectionTime: Date { get }
    var transportType: TransportType { get }
    var handshake: Handshake { get }

    func sendPackets(_ packets: [any Packet]) async
    func sendPacket(_ packet: any Packet) async
    func disconnect() async
}
