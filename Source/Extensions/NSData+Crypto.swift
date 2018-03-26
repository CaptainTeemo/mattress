//
//  NSData+Crypto.swift
//  Mattress
//
//  Created by Kevin Lord on 5/22/15.
//  Copyright (c) 2015 BuzzFeed. All rights reserved.
//

import Foundation
import CommonCrypto

extension Data {
    func mattress_hexString() -> String {
		return self.map { String(format: "%02hhx", $0) }.joined()
    }

    func mattress_MD5() -> Data {
		let messageData = self
		
		var digestData = Data(count: Int(CC_MD5_DIGEST_LENGTH))
		
		_ = digestData.withUnsafeMutableBytes { digestBytes in
			messageData.withUnsafeBytes { messageBytes in
				CC_MD5(messageBytes, CC_LONG(messageData.count), digestBytes)
			}
		}
		
		return digestData
    }

    func mattress_SHA1() -> Data {
		let messageData = self
		
		var digestData = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
		
		_ = digestData.withUnsafeMutableBytes { digestBytes in
			messageData.withUnsafeBytes { messageBytes in
				CC_MD5(messageBytes, CC_LONG(messageData.count), digestBytes)
			}
		}
		
        return digestData
    }
}
