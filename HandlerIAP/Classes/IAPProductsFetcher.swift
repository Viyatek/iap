//
//  IAPProductsFetcher.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//


import Foundation
import StoreKit
import SVProgressHUD
import FirebaseAnalytics

public protocol ProductUIUpdateDelegate {
    func updateUI(products: [SKProduct]?)
}

class IAPProductFetcher {
    
    //Products
    public static var products:  [SKProduct]?
    
    //UI Update Delegate
    public var productUIUpdateDelegate: ProductUIUpdateDelegate?
    
    public func requestProductsFromStore() {
        
        print("Requesting Products From Store")
        IAPProducts.store.requestProducts{ success, products in
            if success {
                
                IAPProductFetcher.products = products
                self.productUIUpdateDelegate?.updateUI(products: products)
                
            }else{
                print("reload is not success")
            }
        }
    }
    
    public func getProduct(byIdentifier identifier: String) -> SKProduct? {
        
        guard let products = IAPProductFetcher.products else{
            return nil
        }
        for p in products{
            
            if p.productIdentifier == identifier{
                return p
            }
        }
        
        return nil
    }
    
}



