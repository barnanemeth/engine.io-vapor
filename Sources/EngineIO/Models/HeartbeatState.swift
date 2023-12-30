//
//  HeartbeatState.swift
//  
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation

enum HeartbeatState {
    case sendingPing
    case waitingForPong
    case sendingPong
}
