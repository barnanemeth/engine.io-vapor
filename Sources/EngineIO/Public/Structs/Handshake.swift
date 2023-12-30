//
//  Handshake.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public struct Handshake {
    public let headers: HTTPHeaders
    public let address: String?
    public let isSecure: Bool
    public let url: URI
    public let parameters: Parameters
}
