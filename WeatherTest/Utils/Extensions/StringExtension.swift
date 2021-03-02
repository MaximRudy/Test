//
//  StringMatchesExtension.swift
//  WeatherTest
//
//  Created by user on 1/19/21.
//

import Foundation

extension String {
    func matches(_ regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
