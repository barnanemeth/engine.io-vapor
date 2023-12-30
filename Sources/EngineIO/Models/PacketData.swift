//
//  PacketData.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

enum PacketData {
    case binary(ByteBuffer)
    case text(String)
}
