//
//  DataManager.swift
//  WeatherTest
//
//  Created by user on 1/6/21.
//

import Combine
import Foundation
import Alamofire

final class DataManager {
    let session: URLSession
    let decoder = JSONDecoder()
    
    init(session: URLSession = .init(configuration: .default)) {
        self.session = session
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
}

// MARK: - Request with city(Alamofire)

extension DataManager {
    func getWeatherAF(for city: String) -> AnyPublisher<WeatherResponse, AFError> {

        let baseUrl = "https://api.openweathermap.org/data/2.5/weather"
        let appid = "302b5b3153622f3d6f42aa61de61076a"
        let lang: String = Locale.current.languageCode ?? ""
        
        let param = ["q": city, "appid": appid, "lang": lang] as [String: Any]
        
        let publisher = AF.request(baseUrl, method: .get, parameters: param)
            .publishDecodable(type: WeatherResponse.self)
            .value()
        
        return publisher
    }
}
