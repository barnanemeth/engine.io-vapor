//
//  BinaryPacket.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public struct BinaryPacket: Packet {

    // MARK: Properties

    public let id = UUID()

    var base64String: String? {
        var byteBuffer = byteBuffer
        guard let data = byteBuffer.readData(length: byteBuffer.readableBytes) else { return nil }
        return data.base64EncodedString()
    }

    // MARK: Private properties

    private let byteBuffer: ByteBuffer

    // MARK: Init

    public init(byteBuffer: ByteBuffer) {
        self.byteBuffer = byteBuffer
    }

    // MARK: Public methods

    public func rawData() -> ByteBuffer {
        byteBuffer
    }
}
