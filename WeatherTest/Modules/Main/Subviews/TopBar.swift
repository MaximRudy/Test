//
//  TopBar.swift
//  WeatherTest
//
//  Created by user on 2/17/21.
//

import SwiftUI

struct TopBar: View {
    
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        HStack {
            NavigationLink(destination: SettingsCV(viewModel: self.viewModel)) {
                Image("menu-dark")
                    .foregroundColor(.primary)
            }
        
            Spacer()
            
            Button(action: {
                self.viewModel.showFindCityCV.toggle()
            }) {
                if !self.viewModel.showFindCityCV {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.primary)
                }
            }
        }
        .padding([.top, .leading, .trailing], 20)
    }
}
