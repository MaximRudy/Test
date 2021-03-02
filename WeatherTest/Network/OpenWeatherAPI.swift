//
//  OpenWeatherAPI.swift
//  WeatherTest
//
//  Created by user on 1/20/21.
//

import CoreLocation
import Combine
import Foundation

extension DataManager {
    
    struct OpenWeatherAPI {
        static let schem: String = "https"
        static let host: String = "api.openweathermap.org"
        static let pathToWeather: String = "/data/2.5/weather"
        static let pathToOnecall: String = "/data/2.5/onecall"
        static let key: String = "302b5b3153622f3d6f42aa61de61076a"
        static let lang: String = Locale.current.languageCode ?? ""
    }
    
    func makeWeatherComponents(latitude: Double, longitude: Double) -> URLComponents {
        var components = URLComponents()
        
        components.scheme = OpenWeatherAPI.schem
        components.host = OpenWeatherAPI.host
        components.path = OpenWeatherAPI.pathToOnecall
        
        components.queryItems = [
            .init(name: "lat", value: "\(latitude)"),
            .init(name: "lon", value: "\(longitude)"),
            .init(name: "appid", value: OpenWeatherAPI.key),
            .init(name: "lang", value: OpenWeatherAPI.lang),
            .init(name: "exclude", value: "minutely")
        ]
        
        return components
    }
    
    func makeWeatherComponents(withCity city: String) -> URLComponents {
        var components = URLComponents()
        
        components.scheme = OpenWeatherAPI.schem
        components.host = OpenWeatherAPI.host
        components.path = OpenWeatherAPI.pathToWeather
        
        components.queryItems = [
            .init(name: "q", value: city),
            .init(name: "appid", value: OpenWeatherAPI.key),
            .init(name: "lang", value: OpenWeatherAPI.lang)
        ]
        return components
    }

}
