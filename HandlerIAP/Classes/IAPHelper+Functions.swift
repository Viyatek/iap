//
//  IAPHelper+Functions.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//


import Foundation
import FirebaseAnalytics
import StoreKit


extension IAPHelper {
    
    public static func checkIfExpirationIsInFuture(expirationDateStr: String) -> Bool{
            
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss VV"
        
        if let expDate = formatter.date(from: expirationDateStr){
            if expDate >= Date(){
                return true
            }else{
                return false
            }
        }else{
            assert(false, "ERROR: checkIfSubscriptionActive")
            return false
        }
    }
    
    static func handleSubscriptionActivation(productId: String?){

        print("Handling Subscription Activation...\(productId ?? "no product idd")")

        if let productId = productId {
            if productId.contains("lifetime") {
                print("this is a life time purchase")
                AUD.set(key: AUD.is_lifetime_member, value: true)
                AUD.set(key: AUD.IS_PRO_MEMBER, value: true)
            } else {
                print("product id issss: \(productId)")
                //MARK: Check is user lifetime member,
                if !AUD.getBool(key: AUD.is_lifetime_member)! {
                    //Date Check
                    guard let expDateStr = AUD.getString(key: AUD.SUBSCRIPTION_EXPIRATION_DATE) else{
                        assert(false)
                        return
                    }
                    
                    if IAPHelper.checkIfExpirationIsInFuture(expirationDateStr: expDateStr)
                    {
                        print("Handling subscription. Switching to premium...")
                        
                        //Switch
                        switchToPremium()
                        

                        
                        //User Property
                        //let property = productId
                        //print("Setting user property: \(property)")
                        let property = "premium"
                        //Analytics.setUserProperty(property, forName: "subscriber_type")
                        /*if property != UDH.getString(key: UDH.SUBSCRIPTION_TYPE)! {
                            Analytics.setUserProperty(property, forName: "user_status")
                        }*/
                        Analytics.setUserProperty(property, forName: "user_status")
                        
                        AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
                        
                        //Set Localized Title for future use
                        setLocalizedTitleForFutureUse(productId: productId)
                        
                    } else {
                        //Grace Period
                        guard let graceExpDateStr = AUD.getString(key: AUD.GRACE_EXPIRATION_DATE) else{
                            assert(false)
                            return
                        }
                        
                        if IAPHelper.checkIfExpirationIsInFuture(expirationDateStr: graceExpDateStr) {
                            print("Handling subscription. User in grace. Switching to premium...")
                            
                            //Switch
                            switchToPremium()
                            
                            //User Property

                            //let property = "grace_\(productId)"
                            //Analytics.setUserProperty(property, forName: "subscriber_type")
                            let property = "ex_premium"
                            /*if property != UDH.getString(key: UDH.SUBSCRIPTION_TYPE)! {
                                Analytics.setUserProperty(property, forName: "user_status")
                            }*/
                            Analytics.setUserProperty(property, forName: "user_status")
                            AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
                            
                            //Set Localized Title for future use
                            setLocalizedTitleForFutureUse(productId: productId)
                            
                            //Warning
                            if let topVC = UIApplication.getTopViewController() {
                               //Alert
                               let alert = UIAlertController(title: "Billing Error", message: "Your subscription can't be renewed and will be cancelled in a short time. Please update your App Store account payment information", preferredStyle: .alert)
                               alert.addAction(UIAlertAction(title: "Update", style: .default, handler: {(UIAlertAction) in
                                let urlString = "https://apps.apple.com/account/billing"
                                if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url){
                                    //Open payment management page
                                    UIApplication.shared.open(url)
                                }
                               }))
                                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                               topVC.present(alert, animated: true)
                            }
                        }
                        else {
                            print("Handling subscription. Switching to basic...")
                            
                            //Switch
                            switchToBasic()
                            
                            //User Property
                            //let property = "ex \(productId)"
                            let property = "ex_premium"
                            print("Setting user property: \(property)")
                            //Analytics.setUserProperty(property, forName: "subscriber_type")
                            /*if property != UDH.getString(key: UDH.SUBSCRIPTION_TYPE)! {
                                Analytics.setUserProperty(property, forName: "user_status")
                            }*/
                            Analytics.setUserProperty(property, forName: "user_status")
                            AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
                            
                            //Set Localized Title for future use
                            setLocalizedTitleForFutureUse(productId: productId)
                        }
                    }
                    
                    //If Refunded Switch To Basic
                    let refunded = AUD.getInt(key: AUD.SUBSCRIPTION_REFUNDED)
                    if refunded == 1 {
                        
                        print("Handling subscription. Switching to basic because refunded!")
                        
                        //Switch
                        switchToBasic()
                        
                        //User Property
                        //let property = "refunded_\(productId)"
                        //Analytics.setUserProperty(property, forName: "subscriber_type")
                        let property = "ex_premium"//"ex_\(productId)"
                        /*if property != UDH.getString(key: UDH.SUBSCRIPTION_TYPE)! {
                            Analytics.setUserProperty(property, forName: "user_status")
                        }*/
                        Analytics.setUserProperty(property, forName: "user_status")
                        AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
                        
                        //Set Localized Title for future use
                        setLocalizedTitleForFutureUse(productId: productId)
                    }
                }
                
            }
        }
  
    }
    
    static func switchToPremium() {
        print("SWITCHING TO PREMIUM")

        if !AUD.getBool(key: AUD.IS_PRO_MEMBER)! {
            let property = "premium"
            AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
            AUD.set(key: AUD.IS_PRO_MEMBER, value: true)
            
            Analytics.setUserProperty(property, forName: "user_status")
        }
        

    }
    
    static func switchToBasic() {
        print("SWITCHING TO BASIC")

        if AUD.getBool(key: AUD.IS_PRO_MEMBER)! {
            let property = "free"
            AUD.set(key: AUD.SUBSCRIPTION_TYPE, value: property)
            AUD.set(key: AUD.IS_PRO_MEMBER, value: false)
            
            Analytics.setUserProperty(property, forName: "user_status")
        }
        

    }
    
    static func setLocalizedTitleForFutureUse(productId: String) {
        //print("product id iss: \(productId) .. \(IAPProductFetcher.products)")
        if let products = IAPProductFetcher.products {
            let subscribedProduct = products.filter({ (skProduct) -> Bool in
                if skProduct.productIdentifier == productId {
                    return true
                }
                return false
            }).first
            
            let plan_type = subscribedProduct?.subscriptionPeriod?.asString()
            AUD.set(key: AUD.SUBSCRIPTION_NAME, value: subscribedProduct?.localizedTitle ?? "")
            AUD.set(key: AUD.price_of_subscribed_product, value: subscribedProduct?.price.doubleValue ?? 0.5)
            AUD.set(key: AUD.plan_type_of_subscribed_product, value: plan_type ?? "")
        }
    }

}

extension SKProductSubscriptionPeriod {
    func asString() -> String {
        let unitCount = self.numberOfUnits
        let unitType = self.unit
        
        switch unitType {
        case .day:
            print("\(unitCount) day\(unitCount > 1 ? "s" : "")")
            return "daily"
        case .week:
            print("\(unitCount) week\(unitCount > 1 ? "s" : "")")
            return "weekly"
        case .month:
            print("\(unitCount) month\(unitCount > 1 ? "s" : "")")
            if unitCount == 3 {
                return "quarterly"
            } else {
                return "monthly"
            }
        case .year:
            print("\(unitCount) year\(unitCount > 1 ? "s" : "")")
            return "yearly"
        @unknown default:
            print("\(unitCount) unit(s)")
            return "lifetime"
        }
    }
}


