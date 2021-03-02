//
//  WeatherError.swift
//  WeatherTest
//
//  Created by user on 1/6/21.
//

import Foundation

enum WeatherError: Error {
    case parsing(message: String)
    case network(message: String)
    case location(message: String)
    case historyIsEmpty(message: String)
    
    var localozeDescription: String {
        switch self {
        case .parsing(let message):
            return message
        case .network(let message):
            return message
        case .location(let message):
            return message
        case .historyIsEmpty(let message):
            return message
        }
    }
}
