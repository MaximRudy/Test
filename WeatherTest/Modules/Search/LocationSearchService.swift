//
//  LocationSearchService.swift
//  WeatherTest
//
//  Created by user on 2/25/21.
//

import Combine
import SwiftUI
import MapKit

final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    
    @Published var isShowingCharts = false
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var weather: Response?
    
    private var weatherFetcher = DataManager()
    private var disposable = Set<AnyCancellable>()
    
    var completer: MKLocalSearchCompleter
    var cancellable: AnyCancellable?
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        cancellable = $searchQuery.assign(to: \.queryFragment, on: self.completer)
        completer.delegate = self
        completer.resultTypes = .address
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError: Error) {
        // Set the results to empty in case the search query is empty or in case there's an uknown error
        self.completions = []
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter the results
        self.completions = completer.results.filter { result in
            
            if result.title.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                return false
            }
            
            if result.subtitle.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                return false
            }
            
            return true
        }
    }
    
    // MARK: - Request for coordinates
    func fetchWeather(_ completion: MKLocalSearchCompletion) {
        
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            guard let coordinate = response?.mapItems[0].placemark.coordinate else {
                return
            }
            let latitude = coordinate.latitude
            let longitude = coordinate.longitude
            
            self.weatherFetcher.currentWeatherForecast(latitude: latitude, longitude: longitude)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] (value) in
                    switch value {
                    case .failure(let error):
                        self?.weather = nil
                        print(error)
                    case .finished:
                        break
                    }
                }) { [weak self] weather in
                    self?.weather = weather
                    self?.isShowingCharts = true
                }.store(in: &self.disposable)
        }
    }
}

extension MKLocalSearchCompletion: Identifiable {}
