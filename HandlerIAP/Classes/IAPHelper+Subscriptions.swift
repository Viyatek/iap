//
//  IAPHelper+Subscriptions.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//


import Foundation
import StoreKit
import FirebaseAnalytics

public typealias SuccessBlock = (String?) -> Void
public typealias FailureBlock = (Error?) -> Void

//#if DEBUG
//    let certificate = "StoreKitTestCertificate"
//#else
//    let certificate = "AppleIncRootCertificate"
//#endif

extension IAPHelper {
    
    //MARK: Refresh Subscriptions Status
    public func refreshSubscriptionsStatus() {
        print("Refreshing Subscriptions Status")
        //Check time to overwhelming server
        /*if Date().timeIntervalSince1970 - self.lastSubscriptionStatusCheck < 1 {
            print("Cancelling status request. Too many!")
            Analytics.logEvent("SubsRequestCanceledTooMany", parameters: nil)
            return
        }*/
        self.lastSubscriptionStatusCheck = Date().timeIntervalSince1970
        
        // save blocks for further use
        self.refreshSubscriptionSuccessBlock = subscriptionSuccessCallback
        self.refreshSubscriptionFailureBlock = subscriptionFailCallback
        guard let receiptUrl = Bundle.main.appStoreReceiptURL else {
                print("Refresh Subscription Status can't decide. Will refresh recepit...")
                refreshReceipt()
                // do not call block yet
                return
        }
        

        
        //Lambda URL
        var urlString = "your_endpoint"//"https://krtiuy73y0.execute-api.us-west-2.amazonaws.com/live/verify-receipt"

        
        //Data
        let receiptData = try? Data(contentsOf: receiptUrl).base64EncodedString()
        //print("REQUEST RECEIPT DATA: \(receiptData ?? "NO DATA!")")
        print("REQUEST RECEIPT DATA:")
        let requestData = ["receipt-data" : receiptData ?? "", "password" : IAPHelper.sharedSecret, "exclude-old-transactions" : true] as [String : Any]
        
        
        //Request
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        let httpBody = try? JSONSerialization.data(withJSONObject: requestData, options: [])
        request.httpBody = httpBody
        
        URLSession.shared.dataTask(with: request)  { (data, response, error) in
            DispatchQueue.main.async {
                if data != nil {
                    if let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments){
                        
                        self.parseReceipt(json as! Dictionary<String, Any>)
                        return
                    }
                } else {
                    print("error validating receipt: \(error?.localizedDescription ?? "")")
                }
                self.refreshSubscriptionFailureBlock?(error)
                self.cleanUpRefeshReceiptBlocks()
            }
        }.resume()
        

        
    }
    
    //MARK: Refresh Receipt
    public func refreshReceipt() {
        print("Inside refreshReceipt")
        let request = SKReceiptRefreshRequest(receiptProperties: nil)
        request.delegate = self
        request.start()
    }
    
    //MARK: Parse Receipt
    public func parseReceipt(_ json : Dictionary<String, Any>) {
        print("Inside parseReceipt")
        //guard let json = json else{return}
        // It's the most simple way to get latest expiration date. Consider this code as for learning purposes. Do not use current code in production apps.
        
        print("RECEIPT JSON: \(json)")
        
        guard let receipts_array = json["latest_receipt_info"] as? [Dictionary<String, Any>] else {
            self.refreshSubscriptionFailureBlock?(nil)
            self.cleanUpRefeshReceiptBlocks()
            print("NO RECEIPT ARRAY")

            return
        }
        
        
        //print("JSON: \(receipts_array)")
      
        //Iterate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss VV"
        var productId: String? = nil
        for receipt in receipts_array {
         
            if let expireDateStr = receipt["expires_date"] as? String {
                
                //Write expiration date to Prefs
                print("=====")
                print("Writing Expiration Date: \(expireDateStr)" )
                //Write to Prefs
                AUD.set(key: AUD.SUBSCRIPTION_EXPIRATION_DATE, value: expireDateStr)
                
                //Check If Refunded
                if let _ = receipt["cancellation_date"] {
                    print("Writing SUBSCRIPTION_REFUNDED = 1")
                    AUD.set(key: AUD.SUBSCRIPTION_REFUNDED, value: 1)
                } else {
                    AUD.set(key: AUD.SUBSCRIPTION_REFUNDED, value: 0)
                }
                
                //Save productId
                productId = receipt["product_id"] as? String
            }
            
            let myProduct = receipt["product_id"] as? String
            if ((myProduct?.contains("lifetime")) != nil) {
                AUD.set(key: AUD.is_lifetime_member, value: true)
                AUD.set(key: AUD.IS_PRO_MEMBER, value: true)
                IAPHelper.setLocalizedTitleForFutureUse(productId: productId ?? "")
            }
            
        }
        
        //Grace Period
        if let pending_renewal_array = json["pending_renewal_info"] as? [Dictionary<String, Any>]{
            for pending_renewal in pending_renewal_array{
                if let graceExpireDateStr = pending_renewal["grace_period_expires_date"] as? String{
                    print("Writing Grace Date: \(graceExpireDateStr)" )
                    AUD.set(key: AUD.GRACE_EXPIRATION_DATE, value: graceExpireDateStr)
                }
            }
        }
        
        print("Product id in refreshSubscriptionSuccessBlock: \(productId ?? "no productt id")")
        self.refreshSubscriptionSuccessBlock?(productId)
        self.cleanUpRefeshReceiptBlocks()
    }
    
    //MARK: CleanUp Refesh Receipt Blocks
    public func cleanUpRefeshReceiptBlocks() {
        self.refreshSubscriptionSuccessBlock = nil
        self.refreshSubscriptionFailureBlock = nil
    }
    
    //Callbacks ========
    //MARK: Subscription SUCCESS Callback
    func subscriptionSuccessCallback(productId: String?)//->Product Id is for setting user property
    {
        print("Sucecss calling refreshSubscriptionsStatus")
        IAPHelper.handleSubscriptionActivation(productId: productId)
        //IAPHelper.shouldRefreshUI()
    }
    
    //MARK: Subscription FAIL Callback
    func subscriptionFailCallback(e: Error?) {
        print("Fail calling refreshSubscriptionsStatus: \(String(describing: e))")
        IAPHelper.handleSubscriptionActivation(productId: nil)

        
        //IAPHelper.shouldRefreshUI()
    }
    
}


enum ReceiptValidationError: Error {
    case receiptNotFound
    case jsonResponseIsNotValid(description: String)
    case notBought
    case expired
}


