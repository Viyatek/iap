//  IAPHelper.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//

import StoreKit
import SVProgressHUD
import Adjust
import FirebaseAnalytics

public typealias ProductIdentifier = String
public typealias ProductsRequestCompletionHandler = (_ success: Bool, _ products: [SKProduct]?) -> Void

extension Notification.Name {
    public static let IAPHelperPurchaseNotification = Notification.Name("IAPHelperPurchaseNotification")
}

public protocol PurchaseSuccessUIUpdateDelegate {
    func purchaseSuccessUpdateUI(productIdentifier: String)
}

open class IAPHelper: NSObject {
    
    //UI Update Delegate
    public var purchaseSuccessUIUpdateDelegate: PurchaseSuccessUIUpdateDelegate?
    
    //App Secret
    public static var sharedSecret = ""

    
    //Price Formatter
    public static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        
        formatter.formatterBehavior = .behavior10_4
        formatter.numberStyle = .currency
        
        return formatter
    }()
    
    public let productIdentifiers: Set<ProductIdentifier>
    public var productsRequest: SKProductsRequest?
    public var productsRequestCompletionHandler: ProductsRequestCompletionHandler?
    
    //For subscription part
    public var refreshSubscriptionSuccessBlock : SuccessBlock?
    public var refreshSubscriptionFailureBlock : FailureBlock?
    public var lastSubscriptionStatusCheck: TimeInterval = 0
    
    //Eligible For Introductory Price
    public static var eligibleForIntroductoryPrice: Bool = true
    
    //Restore Message Run Once
    public var restoreMessageRunOnce = false
    public var restoreOkClickedOnce = false
    public static var selectedProduct: SKProduct?
    public init(productIds: Set<ProductIdentifier>) {
        productIdentifiers = productIds
        super.init()
        SKPaymentQueue.default().add(self)
    }
}

// MARK: - StoreKit API
extension IAPHelper {
    
    public func requestProducts(_ completionHandler: @escaping ProductsRequestCompletionHandler) {
        productsRequest?.cancel()
        productsRequestCompletionHandler = completionHandler
        
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        print("Product identifiers: \(productIdentifiers)")
        productsRequest!.delegate = self
        productsRequest!.start()
    }
    
    //MARK: Buy Product
    public func buyProduct(_ product: SKProduct) {
        
        print("Buying \(product.productIdentifier)...\(product.localizedTitle)")
        
        SVProgressHUD.show()
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    public class func canMakePayments() -> Bool {
        return SKPaymentQueue.canMakePayments()
    }
    
    //MARK: Restore Purchase
    public func restorePurchases() {
        SVProgressHUD.show()
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

// MARK: - SKProductsRequestDelegate
extension IAPHelper: SKProductsRequestDelegate {
    
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        print("Loaded list of products...")
        let products = response.products
        productsRequestCompletionHandler?(true, products)
        clearRequestAndHandler()
    }
    
    //MARK: Request
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        print("IAP Request Failed.")
        print("Error: \(error.localizedDescription)")
        productsRequestCompletionHandler?(false, nil)
        clearRequestAndHandler()
    }
    
    //MARK: Request Finished
    public func requestDidFinish(_ request: SKRequest) {
        print("Inside requestDidFinish")
        // call refresh subscriptions method again with same blocks
        if request is SKReceiptRefreshRequest {
            print("Receipt refresh success! Calling refreshSubscriptionsStatus again...")
            self.refreshSubscriptionsStatus()
        }
    }
    
    //MARK: Clear Request Handler
    public func clearRequestAndHandler() {
        productsRequest = nil
        productsRequestCompletionHandler = nil
    }
}

// MARK: - SKPaymentTransactionObserver
extension IAPHelper: SKPaymentTransactionObserver {
    
    //MARK: Payment Queue
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        print("in payment queue..")
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                SVProgressHUD.dismiss()
                complete(transaction: transaction)
            case .failed:
                SVProgressHUD.dismiss()
                fail(transaction: transaction)
            case .restored:
                SVProgressHUD.dismiss()
                restore(transaction: transaction)
            case .deferred:
                SVProgressHUD.dismiss()
            case .purchasing:
                break
            @unknown default:
                SVProgressHUD.dismiss()
                print("UNKNOWN ERROR IN PAYMENT QUEUE")
            }
        }
    }
    
    //MARK: Complete
    public func complete(transaction: SKPaymentTransaction) {
        Analytics.setUserProperty("premium", forName: "user_status")
        deliverPurchaseNotificationFor(identifier: transaction.payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
                
        buySuccessCompletion(identifier: transaction.payment.productIdentifier) { isLifetime in
            if isLifetime {
                print("this is a life time purchase")
                AUD.set(key: AUD.is_lifetime_member, value: true)
            }
        }
        
        if let selectedProduct = IAPHelper.selectedProduct {
            sendSubscriptionToAdjust(price: selectedProduct.price, currency: selectedProduct.priceLocale.currencyCode!, transaction: transaction)
            if let introductoryPrice = selectedProduct.introductoryPrice, introductoryPrice.paymentMode == .freeTrial {
                reportEventToAdjust(eventCode: "pxtw9x")
            } else {
                reportEventToAdjust(eventCode: "1iyz2t")
            }
        } else {
            sendSubscriptionToAdjust(price: 10, currency: "", transaction: transaction)
        }
        
        print("Purchase complete!")
    }
    
    //MARK: Restore
    public func restore(transaction: SKPaymentTransaction) {
        guard let productIdentifier = transaction.original?.payment.productIdentifier else { return }
        print("restore... \(productIdentifier)")
        deliverPurchaseNotificationFor(identifier: productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
        restoreSuccessCompletion(identifier: productIdentifier)
        print("Restoring Complete")
        //Message
        if let topVC = UIApplication.getTopViewController() {
            if !restoreMessageRunOnce {
                restoreMessageRunOnce = true
                let okAction = UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .default) { [self]
                       UIAlertAction in
                    if !restoreOkClickedOnce {
                        restoreOkClickedOnce = true
                    }
                }
                let alert = UIAlertController(title: NSLocalizedString("Restore", comment: ""), message: NSLocalizedString("restoreSuccess", comment: ""), preferredStyle: .alert)
                alert.addAction(okAction)
                topVC.present(alert, animated: true)
            }
        }
    }
    
    public func fail(transaction: SKPaymentTransaction) {
        print("fail...")
        if let transactionError = transaction.error as NSError?,
            let localizedDescription = transaction.error?.localizedDescription,
            transactionError.code != SKError.paymentCancelled.rawValue {
            print("Transaction Error: \(localizedDescription)")
        }
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    public func deliverPurchaseNotificationFor(identifier: String?) {
        guard let identifier = identifier else { return }
        NotificationCenter.default.post(name: .IAPHelperPurchaseNotification, object: identifier)
    }
    
    func buySuccessCompletion(identifier: String, completion: @escaping(Bool) -> Void) {
        print("Buy Success Completion!!! with \(identifier)")
        IAPHelper.setLocalizedTitleForFutureUse(productId: identifier)
        IAPHelper.temporaryActivation()
        completion(identifier.contains("lifetime"))
        purchaseSuccessUIUpdateDelegate?.purchaseSuccessUpdateUI(productIdentifier: identifier)
    }
    
    public static func temporaryActivation() {
        print("in temporary activation.")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let tomorrow = Date().addingTimeInterval(TimeInterval(86400))
        let tomorrowString = "\(formatter.string(from: tomorrow)) Etc/GMT"
        AUD.set(key: AUD.SUBSCRIPTION_EXPIRATION_DATE, value: tomorrowString)
    }
    
    public func restoreSuccessCompletion(identifier: String) {
        print("Restore Success Completion!!!")
        refreshSubscriptionsStatus()
    }
    
    public func reportEventToAdjust(eventCode: String) {
        let event = ADJEvent(eventToken: eventCode)
        Adjust.trackEvent(event)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        print("in shouldAddStorePayment")
        return true
    }
}

extension IAPHelper {
    
    //Lifetime
    func sendLifetimeReportToAdjust(price: Float, currency: String, transaction: SKPaymentTransaction) {
        print("Reporting lifetime purchase to Adjust. Transaction Identifier: \(String(describing: transaction.transactionIdentifier)), price: \(price), currency: \(currency)")
        let event = ADJEvent(eventToken: "adjustLifetimePurchaseToken")
        event?.setRevenue(Double(price), currency: currency)
        if let transactionId = transaction.transactionIdentifier {
            event?.setTransactionId(transactionId)
        }
        Adjust.trackEvent(event)
    }
    
    //Subscription
    func sendSubscriptionToAdjust(price: NSDecimalNumber, currency: String, transaction: SKPaymentTransaction) {
        print("sending SubscriptionToAdjust")
        guard let transactionId = transaction.transactionIdentifier, let receiptUrl = Bundle.main.appStoreReceiptURL, let receipt = try? Data(contentsOf: receiptUrl) else {
            print("Adjust subscription report error. Parameters are nil")
            return
        }
        
        guard let subscription = ADJSubscription(
            price: price,
            currency: currency,
            transactionId: transactionId,
            andReceipt: receipt) else {
                print("Adjust subscription report error. Subscription object is nil.")
                return
            }
        
        if let date = transaction.transactionDate, let region = Locale.current.regionCode {
            subscription.setTransactionDate(date)
            subscription.setSalesRegion(region)
        }

        Adjust.trackSubscription(subscription)
        print("Adjust subscription successfully tracked. ID: \(subscription.transactionId)")
    }
}

import UIKit

extension UIApplication {
    public class func getTopViewController(base: UIViewController? = UIApplication.shared.connectedScenes
                                        .compactMap { $0 as? UIWindowScene }
                                        .flatMap { $0.windows }
                                        .first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }
}