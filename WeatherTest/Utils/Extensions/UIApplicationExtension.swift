//
//  DismissKeyboard.swift
//  WeatherTest
//
//  Created by user on 1/19/21.
//

import UIKit

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
