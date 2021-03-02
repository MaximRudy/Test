//
//  MetricsRow.swift
//  WeatherTest
//
//  Created by user on 2/17/21.
//

import SwiftUI

struct MetricsRow: View {
    
    var forecast: Response
    var speedUnit: Speed
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(height: 1)
                .opacity(0.1)
            HStack {
                Spacer()
                HStack {
                    Image("humidity")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14)
                    Text("\(forecast.current.humidity)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
                HStack {
                    Image(systemName: "wind")
                        .foregroundColor(.black)
                    FormattedSpeed(speed: forecast.current.windSpeed, unit: speedUnit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.black)
                        .rotationEffect(.degrees(Double(45 - forecast.current.windDeg)))
                        .animation(.spring())
                    Text("\(forecast.current.windDeg)°")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
                HStack {
                    Image(systemName: "cloud")
                        .foregroundColor(.black)
                    Text("\(forecast.current.clouds)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(height: 48)
    }
}
