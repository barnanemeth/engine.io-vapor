//
//  UpgradingState.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

enum UpgradingState: Int, CaseIterable {
    case waitingForPing = 0
    case sendingPong = 1
    case finished = 2

    func increased() -> UpgradingState {
        UpgradingState.allCases.first(where: { $0.rawValue == rawValue + 1 }) ?? self
    }

    func decreased() -> UpgradingState {
        UpgradingState.allCases.first(where: { $0.rawValue == rawValue - 1 }) ?? self
    }
}
