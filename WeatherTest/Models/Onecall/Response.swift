//
//  Response.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct Response: Decodable {
    let lat: Double
    let lon: Double
    let timezone: String
    let timezoneOffset: Int
    let current: CurrentForecast
    let hourly: [HourlyForecast]
    let daily: [DailyForecast]
}
