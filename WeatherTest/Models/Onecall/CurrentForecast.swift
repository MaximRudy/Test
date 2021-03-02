//
//  CurrentForecast.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct CurrentForecast: Decodable {
    let dt: Int
    let sunrise: Int
    let sunset: Int
    let temp: Double
    let feelsLike: Double
    let pressure: Int
    let humidity: Int
    let dewPoint: Double
    let clouds: Int
    let visibility: Int
    let windSpeed: Double
    let windDeg: Int
    let weather: [WeatherObject]
}
