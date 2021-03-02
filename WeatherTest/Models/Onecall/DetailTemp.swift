//
//  DetailTemp.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct DetailTemp: Decodable {
    let day: Double
    let min: Double
    let max: Double
    let night: Double
    let eve: Double
    let morn: Double
}
