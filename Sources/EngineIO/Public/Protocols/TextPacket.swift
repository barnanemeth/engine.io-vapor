//
//  TextPacket.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

public protocol TextPacket: Packet where DataType == String {
    associatedtype PayloadType

    var type: PacketType { get }
    var payload: PayloadType? { get }
}
