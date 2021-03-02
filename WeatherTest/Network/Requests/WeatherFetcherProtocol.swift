//
//  WeatherFetcherProtocol.swift
//  WeatherTest
//
//  Created by user on 1/18/21.
//

import CoreLocation
import Combine
import Foundation

protocol WeatherFetcherProtocol {
    func currentWeatherForecast(for city: String) -> AnyPublisher<WeatherResponse, WeatherError>
    func currentWeatherForecast(latitude: Double, longitude: Double) -> AnyPublisher<Response, WeatherError>
}

extension DataManager {
    
    private func forecast<T>(with components: URLComponents, decoder: JSONDecoder = JSONDecoder()) -> AnyPublisher<T, WeatherError> where T: Decodable {
        guard let url = components.url else {
            let error = WeatherError.network(message: "Could not create URL")
            return Fail(error: error).eraseToAnyPublisher()
        }
        print(url)
        return session.dataTaskPublisher(for: URLRequest(url: url))
            .mapError { error in
                .network(message: error.localizedDescription)
            }
            .flatMap { pair in
                Just(pair.data)
                    .decode(type: T.self, decoder: decoder)
                    .mapError { error in
                        WeatherError.parsing(message: error.localizedDescription)
                    }
            }.eraseToAnyPublisher()
    }
}

extension DataManager: WeatherFetcherProtocol {
    // MARK: - Request for city
    func currentWeatherForecast(for city: String) -> AnyPublisher<WeatherResponse, WeatherError> {
        return forecast(with: makeWeatherComponents(withCity: city))
    }
    
    // MARK: - Request for coordinates
    func currentWeatherForecast(latitude: Double, longitude: Double) -> AnyPublisher<Response, WeatherError> {
        return forecast(with: makeWeatherComponents(latitude: latitude, longitude: longitude), decoder: decoder)
    }
}
