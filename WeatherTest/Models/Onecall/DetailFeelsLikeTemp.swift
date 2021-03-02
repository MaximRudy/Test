//
//  DetailFeelsLikeTemp.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct DetailFeelsLikeTemp: Decodable {
    let day: Double
    let night: Double
    let eve: Double
    let morn: Double
}
