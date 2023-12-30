//
//  CookieOptions.swift
//
//
//  Created by Barna Nemeth on 29/12/2023.
//

import Foundation
import Vapor

public struct CookieOptions {
    public var name: String
    public var expires: Date?
    public var maxAge: Int?
    public var domain: String?
    public var path: String?
    public var isSecure: Bool
    public var isHTTPOnly: Bool
    public var sameSite: HTTPCookies.SameSitePolicy?
}
