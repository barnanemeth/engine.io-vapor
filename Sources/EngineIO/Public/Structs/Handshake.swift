//
//  Handshake.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public struct Handshake {
    let headers: HTTPHeaders
    let address: String?
    let isSecure: Bool
    let url: URI
    let parameters: Parameters
}
