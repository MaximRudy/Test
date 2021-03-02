//
//  Sys.swift
//  WeatherTest
//
//  Created by user on 1/18/21.
//

import Foundation

struct Sys: Codable {
    let type, id: Int?
    let country: String?
    let sunrise, sunset: Int?
}
