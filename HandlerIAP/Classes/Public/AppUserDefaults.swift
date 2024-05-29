//
//  AppUserDefaults.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 29.05.2024.
//




import Foundation

//AppUserDefaults
class AUD {
    public static let OLD_DATE = "2000-01-01 00:00:00 Etc/GMT"
    
    //My Pref Keys
    public static let IS_PRO_MEMBER = "is_pro_member"
    public static let SUBSCRIPTION_EXPIRATION_DATE = "subsExpiryDate"
    public static let GRACE_EXPIRATION_DATE = "graceExpiryDate"
    public static let SUBSCRIPTION_REFUNDED = "subsRefunded"
    public static let SUBSCRIPTION_TYPE = "subsType"
    public static let SUBSCRIPTION_NAME = "SUBSCRIPTION_NAME"
    public static let is_lifetime_member = "is_lifetime_member"
    
    //for event reporting
    public static let plan_type_of_subscribed_product = "plan_type_of_subscribed_product"
    public static let price_of_subscribed_product = "price_of_subscribed_product"
    
    static let defaults = UserDefaults.standard
    
    static func initializeNewUserDefaults() {
        
        set(key: SUBSCRIPTION_EXPIRATION_DATE, value: OLD_DATE)
        set(key: SUBSCRIPTION_REFUNDED, value: false)
        set(key: GRACE_EXPIRATION_DATE, value: OLD_DATE)
        set(key: IS_PRO_MEMBER, value: false)
        set(key: SUBSCRIPTION_TYPE, value: "free")
        set(key: SUBSCRIPTION_NAME, value: "")
        set(key: is_lifetime_member, value: false)
    }
    
    static func set(key: String, value: Any) {
        defaults.set(value, forKey: key)
    }
    
    static func getString(key: String) -> String?{
        if let value = defaults.string(forKey: key){
            return value
        } else {
            return nil
        }
    }
    
    static func getArray(key: String) -> Any {
        return defaults.array(forKey: key)!
    }
    
    static func getInt(key: String) -> Int?{
        return defaults.integer(forKey: key)
    }
    
    static func getBool(key: String) -> Bool?{
        return defaults.bool(forKey: key)
    }
    
    static func getDouble(key: String) -> Double?{
        return defaults.double(forKey: key)
    }
    

}


