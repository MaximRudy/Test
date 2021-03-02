//
//  Weather.swift
//  WeatherTest
//
//  Created by user on 1/18/21.
//

import Foundation

struct Weather: Codable {
    let id: Int?
    let main: String?
    let weatherDescription: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case id
        case main
        case weatherDescription = "description"
        case icon
    }
}
