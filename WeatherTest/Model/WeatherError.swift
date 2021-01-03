//
//  WeatherError.swift
//  WeatherTest
//
//  Created by Максим Рудый on 4.01.21.
//

import Foundation

enum WeatherError: Error {
    case parsing(message: String)
    case network(message: String)
    case location(message: String)
    
    var localizedDescription: String {
        switch self {
        case .parsing(let message):
            return message
        case .network(let message):
            return message
        case .location(let message):
            return message
        }
    }
}
