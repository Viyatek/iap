//
//  IAPProductFetcher.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 27.05.2024.
//

import Foundation
import StoreKit
import SVProgressHUD


protocol ProductUIUpdateDelegate {
    func updateUI(products: [SKProduct]?)
}
