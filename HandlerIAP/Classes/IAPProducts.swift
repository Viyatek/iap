//
//  IAPProducts.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//


import Foundation
import SwiftyJSON

public struct IAPProducts {

    

    
    
    public static var productIdentifiers: Set<ProductIdentifier> = {
    
        return createIdentifiers()

    }()
    
    public static var store = IAPHelper(productIds: IAPProducts.productIdentifiers)
    
    public static var productsJsonValue: JSON?
    

    public static func refreshProductIds() {
        //Refresh product Ids
//        YEARLY_SUBS = RemoteVariables.remoteConfig.configValue(forKey: RemoteVariables.YEARLY_SUBS).stringValue ?? RemoteVariables.YEARLY_SUBS
//        QUARTERLY_SUBS = RemoteVariables.remoteConfig.configValue(forKey: RemoteVariables.QUARTERLY_SUBS).stringValue ?? RemoteVariables.QUARTERLY_SUBS
//        WEEKLY_SUBS = RemoteVariables.remoteConfig.configValue(forKey: RemoteVariables.WEEKLY_SUBS).stringValue ?? RemoteVariables.WEEKLY_SUBS
        //Set Identifiers
        productIdentifiers = createIdentifiers()
        //Set store
        store = IAPHelper(productIds: IAPProducts.productIdentifiers)
    }
    
    static func createIdentifiers() -> Set<ProductIdentifier> {
        var identifiers = Set<ProductIdentifier>()


        if let productsJsonValue = productsJsonValue {
            identifiers.insert(productsJsonValue["first_product"].stringValue)
            identifiers.insert(productsJsonValue["second_product"].stringValue)
            identifiers.insert(productsJsonValue["third_product"].stringValue)
            identifiers.insert(productsJsonValue["lifeTimeProduct"].stringValue)
            identifiers.insert(productsJsonValue["subsProduct"].stringValue)
        }
        return identifiers
        
    }
}

func resourceNameForProductIdentifier(_ productIdentifier: String) -> String? {
    return productIdentifier.components(separatedBy: ".").last
}


