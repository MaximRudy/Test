//
//  SearchCV.swift
//  WeatherTest
//
//  Created by user on 2/21/21.
//

import SwiftUI

struct SearchCV: View {
    
    @ObservedObject var locationSearchService: LocationSearchService
    
    var currentTitles: [String] = []
    
    var body: some View {
        VStack {
            SearchBar(text: $locationSearchService.searchQuery)
            // If there are no items in the results of the search query (completion) AND if the search query is not empty, show the empty state
            if locationSearchService.completions.count == 0 && locationSearchService.searchQuery != "" {
                Spacer()
                Text("No results found.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                // Else show the list
            } else {
                NavigationLink(destination: ChartCV(forecast: self.locationSearchService.weather),
                               isActive: $locationSearchService.isShowingCharts) { EmptyView() }
                List {
                    ForEach(locationSearchService.completions, id: \.self) { completion in
                        Button(action: {
                            self.locationSearchService.fetchWeather(completion)
                        }) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(completion.title)
                                }
                            }
                            .padding([.leading, .trailing], 10)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

struct SearchCV_Previews: PreviewProvider {
    static var previews: some View {
        SearchCV(locationSearchService: LocationSearchService())
    }
}
