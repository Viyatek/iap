//
//  Enc.swift
//  HandlerIAP
//
//  Created by Ömer Karaca on 27.05.2024.
//


import Foundation

class Encyrption {
    
    public static let START_CHAR = 37
    public static let END_CHAR = 38
    
    init() {
        
    }
    
    public static func encrypt(_ text: String) -> String {
        
        let key = arc4random_uniform(5) + 1 // Ensure key is not zero

        var encryptedText = ""

        encryptedText += String(UnicodeScalar(START_CHAR) ?? "%")
        encryptedText += getRandomChar()
        encryptedText += String(key)

        for c in text {
            encryptedText += getRandomChar()

            // Safely unwrap and ensure valid UnicodeScalar
            if let scalarValue = c.unicodeScalars.first?.value,
               let scalar = UnicodeScalar(scalarValue + UInt32(key)) {
                encryptedText += String(scalar)
            } else {
                encryptedText += String(c) // Fallback to the original character if scalar is invalid
            }
            
            encryptedText += getRandomChar()
        }

        encryptedText += String(UnicodeScalar(END_CHAR) ?? "&")

        return encryptedText
    }
    
    public static func resolveEncrypt(_ encryptedText: String) -> String{
        
        var normalText = ""
        
        var canStart = false
        var atStart = true
        var key = 0
        var _i = 0
        for _ in encryptedText//(int i=0; i<encryptedText.length(); i++)
        {
            var index = encryptedText.index(encryptedText.startIndex, offsetBy: _i)
            var c = encryptedText[index]
            
            if(String(c) == String(UnicodeScalar(UInt8(START_CHAR))))
            {canStart = true}
            
            if(canStart == true)
            {
                if(atStart == true)
                {
                    let ind = encryptedText.index(encryptedText.startIndex, offsetBy: _i + 2)
                    let k = encryptedText[ind]
                    key = Int(String(k))!//k.unicodeScalars[k.unicodeScalars.startIndex].value
                    
                    _i = _i + 3 //Dummy char ve key için iki indeks ilerlet
                    //C Refresh
                    index = encryptedText.index(encryptedText.startIndex, offsetBy: _i)
                    c = encryptedText[index]
                    atStart = false
                }
                
                if(Int(c.unicodeScalars[c.unicodeScalars.startIndex].value) == END_CHAR)
                {break}
                
                _i += 1;
                //C Refresh
                index = encryptedText.index(encryptedText.startIndex, offsetBy: _i)
                c = encryptedText[index]
                
                normalText = normalText + String(UnicodeScalar(UInt8(Int(c.unicodeScalars[c.unicodeScalars.startIndex].value) - key)));
                
                _i += 1;
                //C Refresh
                index = encryptedText.index(encryptedText.startIndex, offsetBy: _i)
                c = encryptedText[index]
                
            }
            
            _i += 1
        }
        
        return normalText;
    }
    
    public static func getRandomChar() -> String{
        
        let num = arc4random_uniform((122-48)+1) + 48;//numbers, signs and letters in ascii
        
        return String(UnicodeScalar(UInt8(num)))
    }
    
    public static func doubleCrypt(text: String) -> String{
        
        return text
        
        //BYPASS
        
//        let enc1 = Encyrption.encrypt(text)
//        let enc2 = Encyrption.encrypt(enc1)
//        return enc2
    }
    
    public static func resolveDoubleCrypt(text: String) -> String{
        let res1 = Encyrption.resolveEncrypt(text)
        let res2 = Encyrption.resolveEncrypt(res1)
        return res2
    }

    
    /*
     let str = "Hello, world!"
     let index = str.index(str.startIndex, offsetBy: 4)
     str[index] // returns Character 'o'
     
     let endIndex = str.index(str.endIndex, offsetBy:-2)
     str[index ..< endIndex] // returns String "o, worl"
     
     String(str.suffix(from: index)) // returns String "o, world!"
     String(str.prefix(upTo: index)) // returns String "Hell"
     */
    
}

