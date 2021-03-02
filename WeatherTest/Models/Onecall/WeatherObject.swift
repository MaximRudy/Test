//
//  WeatherObject.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct WeatherObject: Decodable {
    let id: Int
    let main: MainWeatherType
    let description: String
}
