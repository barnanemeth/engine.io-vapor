//
//  Task+Extensions.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

extension Task where Failure == Never, Success == Never {
    static func sleep(milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(milliseconds * 1_000_000))
    }
}
