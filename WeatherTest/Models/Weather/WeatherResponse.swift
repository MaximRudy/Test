//
//  Weather.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//
import Foundation
// MARK: - WeatherResponse
struct WeatherResponse: Codable, Identifiable {
    let uuid = UUID()
    let coord: Coord?
    let weather: [Weather]?
    let base: String?
    let main: Main?
    let visibility: Int?
    let wind: Wind?
    let clouds: Clouds?
    let dt: TimeInterval?
    let sys: Sys?
    let timezone: Int?
    let id: Int?
    let name: String?
    let cod: Int?
}
