//
//  Handshake+Extensions.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

extension Handshake {
    init(from request: Request) {
        self.headers = request.headers
        self.address = request.remoteAddress?.ipAddress
        self.isSecure = request.url.scheme == "https"
        self.url = request.url
        self.parameters = request.parameters
    }
}
