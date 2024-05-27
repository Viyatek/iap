//
//  IAPHelper.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 27.05.2024.
//

import StoreKit
import SVProgressHUD
import Adjust

public typealias ProductIdentifier = String
public typealias ProductsRequestCompletionHandler = (_ success: Bool, _ products: [SKProduct]?) -> Void


extension Notification.Name {
    static let IAPHelperPurchaseNotification = Notification.Name("IAPHelperPurchaseNotification")
}

protocol PurchaseSuccessUIUpdateDelegate {
    func purchaseSuccessUpdateUI(productIdentifier: String)
}

open class IAPHelper: NSObject  {
    
}
