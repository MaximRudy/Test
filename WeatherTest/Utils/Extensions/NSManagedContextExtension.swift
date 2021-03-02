//
//  NSManagedContextExtension.swift
//  WeatherTest
//
//  Created by user on 1/29/21.
//

import UIKit
import CoreData

extension NSManagedObjectContext {
    
    static var current: NSManagedObjectContext {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        return appDelegate.persistentContainer.viewContext
    }
    
}
