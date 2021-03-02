//
//  WeatherCard.swift
//  WeatherTest
//
//  Created by user on 2/17/21.
//

import SwiftUI

struct WeatherCard: View {
    
    var cityName: String?
    var forecast: Response!
    var tempUnit: Temperature = .celsius
    var speedUnit: Speed = .kmh
    
    var gradient: [Color] {
        return gradients[currentDayPart] ?? [Color.white]
    }
    
    var currentDayPart: MainDaypart {
        return getDayPart(sunrise: Double(forecast.current.sunrise),
                          sunset: Double(forecast.current.sunset),
                          nextDaySunrise: Double(forecast.daily[1].sunrise),
                          timestamp: Double(forecast.current.dt))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 15.0)
                    .fill(LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: UnitPoint(x: 0.5, y: 0.2),
                            endPoint: UnitPoint(x: 0.5, y: 0.5)))
                    .shadow(color: Color(#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.25)), radius: 10, x: 0, y: 4)
                
                // Temperature, conditions, feels like
                VStack {
                    HStack {
                        FormattedTemperature(temperature: forecast.current.temp, unit: tempUnit)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(forecast.current.weather[0].description)".capitalized)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                            HStack(spacing: 3) {
                                Text("Feels like".localized)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                FormattedTemperature(temperature: forecast.current.feelsLike, unit: tempUnit)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                    }.padding(15)
                    
                    Text(cityName ?? "")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundColor(.white)
                    Text("\(getDate(forecast.current.dt))")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 15.0)
                            .fill(LinearGradient(
                                    gradient: Gradient(colors: gradient),
                                    startPoint: UnitPoint(x: 0.5, y: 0),
                                    endPoint: UnitPoint(x: 0.5, y: 0.5)))
                            .shadow(color: Color(#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.25)), radius: 10, x: 0, y: 4)
                        VStack(spacing: 0) {
                            Spacer()
                            if currentDayPart != MainDaypart.night {
                                SunDial(sunrise: forecast.current.sunrise, sunset: forecast.current.sunset, timestamp: forecast.current.dt, timezone: forecast.timezone)
                            } else {
                                VStack {
                                    Text("Next sunrise at".localized + " \(getNextSunriseTime(forecast.current.sunrise))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                }
                                .frame(height: 70)
                                .padding(.leading, 5)
                                .padding(.trailing, 5)
                            }
                             MetricsRow(forecast: forecast, speedUnit: speedUnit)
                        }
                    }
                    .frame(height: currentDayPart == MainDaypart.night ? 125 : geometry.size.height / 3.5 + 74)
                }
                Spacer()
            }
            .padding(10)
        }
    }
}

func getDate(_ timestamp: Int) -> String {
    
    var date: Date { Date(timeIntervalSince1970: Double(timestamp)) }
    let formatter = DateFormatter.dateFormatter
    var formattedDate: String {formatter.string(from: date)}
    
    return formattedDate
}

func getNextSunriseTime(_ sunrise: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(sunrise))
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.locale = NSLocale.current
    var formattedDate: String {formatter.string(from: date)}
    
    return formattedDate
}
