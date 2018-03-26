//
//  DiskCacheTests.swift
//  Mattress
//
//  Created by David Mauro on 11/14/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import XCTest

class DiskCacheTests: XCTestCase {

    override func setUp() {
        // Ensure plist on disk is reset
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 0)
        if let path = diskCache.diskPathForPropertyList()?.path {
			try! FileManager.default.removeItem(atPath: path)
        }
    }

    func testDiskPathForRequestIsDeterministic() {
        let url = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url)
        let request2 = URLRequest(url: url)
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
		let path = diskCache.diskPathForRequest(request: request1)
        XCTAssertNotNil(path, "Path for request was nil")
		XCTAssert(path == diskCache.diskPathForRequest(request: request2), "Requests for the same url did not match")
    }

    func testDiskPathsForDifferentRequestsAreNotEqual() {
        let url1 = URL(string: "foo://bar")!
        let url2 = URL(string: "foo://baz")!
        let request1 = URLRequest(url: url1)
        let request2 = URLRequest(url: url2)
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
		let path1 = diskCache.diskPathForRequest(request: request1)
		let path2 = diskCache.diskPathForRequest(request: request2)
        XCTAssert(path1 != path2, "Paths should not be matching")
    }

    func testStoreCachedResponseReturnsTrue() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
		let cachedResponse = cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: ["foo" : "bar"])
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
		let success = diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
        XCTAssert(success, "Did not save the cached response to disk")
    }

    func testCachedResponseCanBeArchivedAndUnarchivedWithoutDataLoss() {
        // Saw some old reports of keyedArchiver not working well with NSCachedURLResponse
        // so this is just here to make sure things are working on Apple's end
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
		let cachedResponse = cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: ["foo" : "bar"])
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)

		let restored = diskCache.cachedResponseForRequest(request: request)
        if let restored = restored {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testCacheReturnsCorrectResponseForRequest() {
        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
		let cachedResponse1 = cachedResponseWithDataString(dataString: "hello, world", request: request1, userInfo: ["foo" : "bar"])

        let url2 = URL(string: "foo://baz")!
        let request2 = URLRequest(url: url2)
		let cachedResponse2 = cachedResponseWithDataString(dataString: "goodbye, cruel world", request: request2, userInfo: ["baz" : "qux"])

		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
		let success1 = diskCache.storeCachedResponse(cachedResponse: cachedResponse1, forRequest: request1)
		let success2 = diskCache.storeCachedResponse(cachedResponse: cachedResponse2, forRequest: request2)
        XCTAssert(success1 && success2, "The responses did not save properly")
		
		let restored1 = diskCache.cachedResponseForRequest(request: request1)
        if let restored = restored1 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse1)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
		let restored2 = diskCache.cachedResponseForRequest(request: request2)
        if let restored = restored2 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse2)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testStoredRequestIncrementsDiskCacheSizeByFilesize() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
		let cachedResponse = cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: ["foo" : "bar"])
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
        XCTAssert(diskCache.currentSize == 0, "Current size should start zeroed out")
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
		if let path = diskCache.diskPathForRequest(request: request)?.path {
			let attributes = try! FileManager.default.attributesOfItem(atPath: path)
			if let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
				let size = fileSize.intValue
                XCTAssert(diskCache.currentSize == size, "Disk cache size was not incremented by the correct amount")
            } else {
                XCTFail("Could not get fileSize from attribute")
            }
        } else {
            XCTFail("Did not get a valid path for request")
        }
    }

    func testStoringARequestIncreasesTheRequestCachesSize() {
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
		let cachedResponse = cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: nil)
        XCTAssert(diskCache.requestCaches.count == 0, "Should not start with any request caches")
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
        XCTAssert(diskCache.requestCaches.count == 1, "requestCaches should be 1")
    }

    func testFilesAreRemovedInChronOrderWhenCacheExceedsMaxSize() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
		let cachedResponse1 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request1, userInfo: nil)

        let url2 = URL(string: "bar://baz")!
        let request2 = URLRequest(url: url2)
		let cachedResponse2 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request2, userInfo: nil)

        let url3 = URL(string: "baz://qux")!
        let request3 = URLRequest(url: url3)
		let cachedResponse3 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request2, userInfo: nil)

		diskCache.storeCachedResponse(cachedResponse: cachedResponse1, forRequest: request1)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse2, forRequest: request2)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse3, forRequest: request3) // This should cause response1 to be removed

		let requestCaches = [diskCache.hashForURLString(string: url2.absoluteString)!, diskCache.hashForURLString(string: url3.absoluteString)!]
        XCTAssert(diskCache.requestCaches == requestCaches, "Request caches did not match expectations")
    }

    func testPlistIsUpdatedAfterStoringARequest() {
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
		let cachedResponse = cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: nil)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)

		let data = NSKeyedArchiver.archivedData(withRootObject: cachedResponse)
		let expectedSize = data.count
        let expectedRequestCaches = diskCache.requestCaches
        if let plistPath = diskCache.diskPathForPropertyList()?.path {
			if FileManager.default.fileExists(atPath: plistPath) {
                if let dict = NSDictionary(contentsOfFile: plistPath) {
					if let currentSize = dict.value(forKey: DiskCache.DictionaryKeys.maxCacheSize) as? Int {
                        XCTAssert(currentSize == expectedSize, "Current size did not match expected value")
                    } else {
                        XCTFail("Plist did not have currentSize property")
                    }
					if let requestCaches = dict.value(forKey: DiskCache.DictionaryKeys.requestsFilenameArray) as? [String] {
                        XCTAssert(requestCaches == expectedRequestCaches, "Request caches did not match expected value")
                    } else {
                        XCTFail("Plist did not have requestCaches property")
                    }
                }
            } else {
                XCTFail("Could not find plist")
            }
        } else {
            XCTFail("Could not get plist path")
        }
    }

    func testDiskCacheRestoresPropertiesFromPlist() {
        var expectedRequestCaches: [String] = []
        var expectedSize = 0
        autoreleasepool { [unowned self] in
			let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
            let url = URL(string: "foo://bar")!
            let request = URLRequest(url: url)
			let cachedResponse = self.cachedResponseWithDataString(dataString: "hello, world", request: request, userInfo: nil)
			diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
            expectedRequestCaches = diskCache.requestCaches
            expectedSize = diskCache.currentSize
        }
		let newDiskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        XCTAssert(newDiskCache.currentSize == expectedSize, "Size property did not match expectations")
        XCTAssert(newDiskCache.requestCaches == expectedRequestCaches, "RequestCaches did not match expectations")
    }

    func testRequestCacheIsRemovedFromDiskAfterTrim() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
		let cachedResponse1 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request1, userInfo: nil)
		let pathForResponse = (diskCache.diskPathForRequest(request: request1)?.path)!

        let url2 = URL(string: "bar://baz")!
        let request2 = URLRequest(url: url2)
		let cachedResponse2 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request2, userInfo: nil)

        let url3 = URL(string: "baz://qux")!
        let request3 = URLRequest(url: url3)
		let cachedResponse3 = cachedResponseWithDataOfSize(dataSize: dataSize, request: request2, userInfo: nil)

		diskCache.storeCachedResponse(cachedResponse: cachedResponse1, forRequest: request1)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse2, forRequest: request2)
		var isFileOnDisk = FileManager.default.fileExists(atPath: pathForResponse)
        XCTAssert(isFileOnDisk, "File should be on disk")
		diskCache.storeCachedResponse(cachedResponse: cachedResponse3, forRequest: request3) // This should cause response1 to be removed
		isFileOnDisk = FileManager.default.fileExists(atPath: pathForResponse)
        XCTAssertFalse(isFileOnDisk, "File should no longer be on disk")
    }

    func testiOS7CanSaveCachedResponse() {
		if #available(iOS 8.0, *) {
			XCTAssert(true)
			return
		}
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let dataSize = cacheSize/3 + 1
		let diskCache = DiskCacheiOS7(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)

        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
		let cachedResponse = cachedResponseWithDataOfSize(dataSize: dataSize, request: request, userInfo: userInfo)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
		let basePath = (diskCache.diskPathForRequest(request: request)?.path)!

		let responsePath = diskCache.hashForResponseFromHash(hash: basePath)
		let dataPath = diskCache.hashForDataFromHash(hash: basePath)
		let userInfoPath = diskCache.hashForUserInfoFromHash(hash: basePath)

		XCTAssert(FileManager.default.fileExists(atPath: responsePath), "Response file should be on disk")
		XCTAssert(FileManager.default.fileExists(atPath: dataPath), "Data file should be on disk")
		XCTAssert(FileManager.default.fileExists(atPath: userInfoPath), "User Info file should be on disk")
    }

    func testiOS7CanRestoreCachedResponse() {
		if #available(iOS 8.0, *) {
			XCTAssert(true)
			return
		}
		
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let dataSize = cacheSize/3 + 1
		let diskCache = DiskCacheiOS7(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)

        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
		let cachedResponse = cachedResponseWithDataOfSize(dataSize: dataSize, request: request, userInfo: userInfo)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)

		if let response = diskCache.cachedResponseForRequest(request: request) {
            assertCachedResponsesAreEqual(response1: response, response2: cachedResponse)
        } else {
            XCTFail("Could not retrieve cached response")
        }
    }

    func testClearCacheRemovesAnyExistingRequests() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
        let dataSize = 1
		let cachedResponse = cachedResponseWithDataOfSize(dataSize: dataSize, request: request, userInfo: userInfo)
		let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024*1024)
		diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
        diskCache.clearCache()
		XCTAssertFalse(diskCache.hasCacheForRequest(request: request))
    }

    // Mark: - Test Helpers

	func assertCachedResponsesAreEqual(response1: CachedURLResponse, response2: CachedURLResponse) {
        XCTAssert(response1.data == response2.data, "Data did not match")
		XCTAssert(response1.response.url == response2.response.url, "Response did not match")
		guard let userInfo1 = response1.userInfo, let userInfo2 = response2.userInfo else {
			XCTFail("userInfo did not match")
			return
		}
		let userInfoEqual = userInfo1.description == userInfo2.description
		XCTAssert(userInfoEqual, "userInfo didn't match")
    }

	func cachedResponseWithDataString(dataString: String, request: URLRequest, userInfo: [AnyHashable : Any]?) -> CachedURLResponse {
		let data = dataString.data(using: .utf8, allowLossyConversion: false)!
        let response = URLResponse(url: request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: nil)
		let userInfoDic = NSDictionary(dictionary: userInfo ?? [:])
		let cachedResponse = CachedURLResponse(response: response, data: data, userInfo: userInfoDic as? [AnyHashable: Any], storagePolicy: .allowed)
        return cachedResponse
    }

    func cachedResponseWithDataOfSize(dataSize: Int, request: URLRequest, userInfo: [AnyHashable : Any]?) -> CachedURLResponse {
		var bytes: [UInt32] = Array(repeating: 1, count: dataSize)
        let data = Data(bytes: &bytes, count: dataSize)
        let response = URLResponse(url: request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: nil)
		let userInfoDic = NSDictionary(dictionary: userInfo ?? [:])
		let cachedResponse = CachedURLResponse(response: response, data: data, userInfo: userInfoDic as? [AnyHashable: Any], storagePolicy: .allowed)
        return cachedResponse
    }
}

class DiskCacheiOS7: DiskCache {
    override var isAtLeastiOS8: Bool {
        return false
    }
}
