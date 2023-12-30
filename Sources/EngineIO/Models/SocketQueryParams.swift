//
//  SocketQueryParams.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

struct SocketQueryParams {

    // MARK: Constants

    private enum Constant {
        static let engineVersionKey = "EIO"
        static let transportKey = "transport"
        static let idKey = "sid"
    }

    // MARK: Properties

    let engineVersion: EngineVersion
    let transportType: TransportType
    let id: String?

    // MARK: Init

    init(from request: Request) throws {
        guard let engiveVersionValue = request.query[Int.self, at: Constant.engineVersionKey],
              let transportTypeValue = request.query[String.self, at: Constant.transportKey],
              let engineVersion = EngineVersion(rawValue: engiveVersionValue),
              let transportType = TransportType(rawValue: transportTypeValue) else {
            throw Abort(.badRequest)
        }
        self.engineVersion = engineVersion
        self.transportType = transportType
        self.id = request.query[String.self, at: Constant.idKey]
    }

    // MARK: Public methods

    func getID() throws -> String {
        guard let id else { throw Abort(.badRequest) }
        return id
    }
}
