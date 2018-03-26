//
//  URLCache.swift
//  Mattress
//
//  Created by David Mauro on 11/12/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import Foundation

public typealias NSURLCache = Foundation.URLCache
/**
    Key used for a boolean property set on URLRequests by a
    WebViewCacher to indicate they should be stored in the cache.
*/
public let MattressCacheRequestPropertyKey = "MattressCacheRequest"
/// Used to avoid hitting the cache when online
public let MattressAvoidCacheRetreiveOnlineRequestPropertyKey = "MattressAvoidCacheRetreiveOnlineRequestPropertyKey"

private let kB = 1024
private let MB = kB * 1024
private let ArbitrarilyLargeSize = MB * 100

/**
    URLCache is an NSURLCache with an additional diskCache used
    only for storing requests that should be available without
    hitting the network.
*/
public class URLCache: NSURLCache {
    // Handler used to determine if we're offline
    var isOfflineHandler: (() -> Bool)?

    // Associated disk cache
    var diskCache: DiskCache

    // Array of WebViewCacher objects used to cache pages
    var cachers: [WebViewCacher] = []

    /*
    We need to override this because the connection
    might decide not to cache something if it decides
    the cache is too small wrt the size of the request
    to be cached.
    */
    override public var diskCapacity: Int {
        get {
            return ArbitrarilyLargeSize
        }
        set (value) {}
    }

    // MARK: - Class Methods

    /**
        Determines whether a request should be cached in Mattress for later use.

        :param: request The request

        :returns: A boolean of whether the request should be cached.
    */
    class func requestShouldBeStoredInMattress(request: URLRequest) -> Bool {
		if let value = NSURLProtocol.property(forKey: MattressCacheRequestPropertyKey, in: request) as? Bool {
            return value
        }
        return false
    }

    // MARK: - Instance Methods

    /**
        Initializes a URLCache.

        :param: memoryCapacity The memory capacity of the cache in bytes
        :param: diskCapacity The disk capacity of the cache in bytes
        :param: diskPath The location in the application's default cache
            directory at which to store the on-disk cache
        :param: mattressDiskCapacity The disk capacity of the cache dedicated
            to requests that should be available via Mattress
        :param: mattressDiskPath The location at which to store the Mattress
            disk cache, relative to the specified mattressSearchPathDirectory
        :param: mattressSearchPathDirectory The searchPathDirectory to use as
            the location for the Mattress disk cache
        :param: isOfflineHandler A handler that will be called as needed to
            determine if the Mattress cache should be used
    */
    public init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?, mattressDiskCapacity: Int, mattressDiskPath: String?,
				mattressSearchPathDirectory searchPathDirectory: FileManager.SearchPathDirectory, isOfflineHandler: (() -> Bool)?)
    {
        diskCache = DiskCache(path: mattressDiskPath, searchPathDirectory: searchPathDirectory, maxCacheSize: mattressDiskCapacity)
        self.isOfflineHandler = isOfflineHandler
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path)
		addToProtocol(shouldAdd: true)
    }

    deinit {
		addToProtocol(shouldAdd: false)
    }

    /**
        Adds or removes the URLCache to/from the URLProtocol caches.
    
        :param: shouldAdd If true, adds the cache. Otherwise, removes.
    */
    func addToProtocol(shouldAdd: Bool) {
        if shouldAdd {
			URLProtocol.addCache(cache: self)
        } else {
			URLProtocol.removeCache(cache: self)
        }
    }

    /**
        Attempts to find a WebViewCacher responsible
        for a given request.
    
        :param: request The request
    
        :returns: The WebViewCacher responsible for the request if found,
            otherwise nil.
    */
    func webViewCacherOriginatingRequest(request: URLRequest) -> WebViewCacher? {
        for cacher in cachers {
			if cacher.didOriginateRequest(request: request) {
                return cacher
            }
        }
        return nil
    }

    /**
        Stores the cached response into the diskCache only if the response
        is valid (statusCode < 400).
    
        :param: cachedResponse The NSCachedURLResponse to store in diskCache.
        :param: request The URLRequest this response is associated with.
    */
	func storeCachedResponseInDiskCache(cachedResponse: CachedURLResponse, forRequest request: URLRequest) {
        // We should never store failure responses
		if let httpResponse = cachedResponse.response as? HTTPURLResponse {
            if httpResponse.statusCode < 400 {
				diskCache.storeCachedResponse(cachedResponse: cachedResponse, forRequest: request)
            }
        }
    }

    // MARK: Public

    public func clearDiskCache() {
        diskCache.clearCache()
    }

	public override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
		if URLCache.requestShouldBeStoredInMattress(request: request) {
			storeCachedResponseInDiskCache(cachedResponse: cachedResponse, forRequest: request)
        } else {
			super.storeCachedResponse(cachedResponse, for: request)
            // If we've already stored this in the Mattress cache, update it
			if diskCache.hasCacheForRequest(request: request) {
				storeCachedResponseInDiskCache(cachedResponse: cachedResponse, forRequest: request)
            }
        }
    }

	override public func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
		let cachedResponse = diskCache.cachedResponseForRequest(request: request)
        if cachedResponse != nil {
            return cachedResponse
        }
		return super.cachedResponse(for: request)
    }

    internal func hasMattressCachedResponseForRequest(request: URLRequest) -> Bool{
		return diskCache.hasCachedResponseForRequest(request: request)
    }

    /**
        Downloads and stores an entire page in the diskCache. Any urls
        cached in this way will be available when the device is offline.

        :param: url The url of a webpage to download
        :param: loadedHandler A handler that will be called every time the
            UIWebView used to load the request calls its delegate's
            webViewDidFinishLoad method. This handler will receive the webView
            and should return true if we are done loading the page, or false
            if we should continue loading.
        :param: completeHandler A handler called once the process has been 
            completed.
        :param: failureHandler A handler with a single error parameter called
            in case of failure.
    */
    public func diskCacheURL(url: URL,
							 loadedHandler: @escaping WebViewLoadedHandler,
                    completeHandler: (() ->Void)? = nil,
                     failureHandler: ((Error) ->Void)? = nil) {
        let webViewCacher = WebViewCacher()
        
		synchronized(lockObj: self) {
            self.cachers.append(webViewCacher)
        }
        
        var failureHandler = failureHandler
        var completeHandler = completeHandler

		webViewCacher.mattressCacheURL(url: url, loadedHandler: loadedHandler, completionHandler: { (webViewCacher) -> () in
			synchronized(lockObj: self) {
				if let index = self.cachers.index(of: webViewCacher) {
					self.cachers.remove(at: index)
                }
                
                completeHandler?()
                completeHandler = nil
            }
            }, failureHandler: { (error) -> () in
                failureHandler?(error)
                failureHandler = nil
            })
        }
}
