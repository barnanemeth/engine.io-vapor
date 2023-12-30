//
//  Packet.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

public protocol Packet: Sendable {
    associatedtype DataType

    var id: UUID { get }
    func rawData() -> DataType
}
