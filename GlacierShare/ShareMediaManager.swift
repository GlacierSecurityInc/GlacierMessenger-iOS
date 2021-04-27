//
//  ShareMediaManager.swift
//  GlacierShare
//
//  Created by Andy Friedman on 1/5/21.
//  Copyright © 2021 Glacier. All rights reserved.
//

import Foundation
import XMPPFramework
import CocoaLumberjack
import OTRKit
import Alamofire

extension UIImage {
    enum DataSize {
        case unlimited
        case maxBytes(UInt)
        var numBytes: UInt {
            switch self {
            case .unlimited:
                return UInt.max
            case .maxBytes(let limit):
                return limit
            }
        }
    }
     struct Quality {
        //static let low = Quality(initial: 0.4, decrementFactor: 0.65)
        //static let medium = Quality(initial: 0.65, decrementFactor: 0.65)
        static let low = Quality(initial: 0.3, decrementFactor: 0.3)
        static let medium = Quality(initial: 0.5, decrementFactor: 0.5)
        static let high = Quality(initial: 0.75, decrementFactor: 0.75)
        
        /// This value cannot be > 1 or bad things will happen
        let initial: CGFloat
        /// Multiplied to reduce the initial value. This value cannot be > 1 or bad things will happen
        let decrementFactor: CGFloat
    }
    func jpegData(dataSize: DataSize,
                  resize: Quality = Quality.medium,
                  jpeg: Quality = Quality.low,
                  maxTries: UInt = 10) -> Data? {
        let image = self
        //var scaledImageData: Data? = nil
        let scaledImageData = UIImageJPEGRepresentation(image, 0.5)
        return scaledImageData
    }
}



public enum ShareMediaError: LocalizedError, CustomNSError {
    case unknown
    case noServers
    case serverError
    case exceedsMaxSize
    case urlFormatting
    case fileNotFound
    case keyGenerationError
    case cryptoError
    case automaticDownloadsDisabled
    case userCanceled
    
    public var errorUserInfo: [String : Any] {
        if let errorDescription = self.errorDescription {
            return [NSLocalizedDescriptionKey: errorDescription];
        }
        return [:]
    }
    
    // localizedDescription
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return UNKNOWN_ERROR_STRING()
        case .noServers:
            return NO_HTTP_UPLOAD_SERVERS_STRING() + " " + PLEASE_CONTACT_SERVER_OP_STRING()
        case .serverError:
            return UNKNOWN_ERROR_STRING() + " " + PLEASE_CONTACT_SERVER_OP_STRING()
        case .exceedsMaxSize:
            return FILE_EXCEEDS_MAX_SIZE_STRING()
        case .urlFormatting:
            return COULD_NOT_PARSE_URL_STRING()
        case .fileNotFound:
            return FILE_NOT_FOUND_STRING()
        case .cryptoError, .keyGenerationError:
            return errSSLCryptoString()
        case .automaticDownloadsDisabled:
            return AUTOMATIC_DOWNLOADS_DISABLED_STRING()
        case .userCanceled:
            return USER_CANCELED_STRING()
        }
    }
}

public class ShareMediaManager: NSObject {

    let httpFileUpload: XMPPHTTPFileUpload
    var connection: YapDatabaseConnection?
    let internalQueue = DispatchQueue(label: "ShareMediaManager Queue")
    let callbackQueue = DispatchQueue.main
    let sessionManager: Session
    let uploadDomain: String
    let shareDelegate: ShareMessageDelegate
    private var servers: [HTTPServer] = []
    
    @objc public var canUploadFiles: Bool {
        return self.servers.first != nil
    }
    
    deinit {
        httpFileUpload.removeDelegate(self)
    }
    
    @objc public init(connection: YapDatabaseConnection,
                      sessionConfiguration: URLSessionConfiguration,
                      delegate: ShareMessageDelegate,
                      xmppStream: XMPPStream,
                      uploadDomain: String) {
        self.httpFileUpload = XMPPHTTPFileUpload()
        self.connection = connection
        self.sessionManager = Alamofire.Session(configuration: sessionConfiguration)
        self.uploadDomain = uploadDomain
        self.shareDelegate = delegate
        super.init()
        
        //create default HTTPServer
        //ideally this info is retrieved from server, but we don't want to discover services here
        //these are just a default/guess and may not work
        if let jid = XMPPJID(string: "upload." + uploadDomain) {
            let maxSize:UInt = 104857600
            let server = HTTPServer(jid: jid, maxSize: maxSize)
            servers.append(server)
        }
        
        httpFileUpload.activate(xmppStream)
        httpFileUpload.addDelegate(self, delegateQueue: DispatchQueue.main)
    }
    
    @objc public func removeDelegates() {
        httpFileUpload.removeDelegate(self)
    }
    
    @objc public func teardownConnections() {
        self.connection = nil
    }
    
    // MARK: - Public Methods
    
    @objc public func compressImage(_ imageURL: URL, to pointSize: CGSize, scale: CGFloat) -> UIImage {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
     
        let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions)!
      
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions =  [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                  kCGImageSourceShouldCacheImmediately: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels] as CFDictionary
        let downsampledImage =   CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)!
        return UIImage(cgImage: downsampledImage)
    }

    private func upload(mediaItem: OTRMediaItem,
                        shouldEncrypt: Bool,
                       prefetchedData: Data?,
                       completion: @escaping (_ url: URL?, _ error: Error?) -> ()) {
        internalQueue.async {
            if let data = prefetchedData {
                self.upload(media: mediaItem, data: data, shouldEncrypt: shouldEncrypt, filename: mediaItem.filename, contentType: mediaItem.mimeType, completion: completion)
            } else {
                let error = ShareMediaError.fileNotFound
                DDLogError("Upload failed: Could not get file data \(error)")
                self.callbackQueue.async {
                    completion(nil, error)
                }
            }/*else {
                var url: URL? = nil
                self.connection.read({ (transaction) in
                    url = mediaItem.mediaServerURL(with: transaction)
                })
                if let url = url {
                    self.upload(media: mediaItem, file: url, shouldEncrypt: shouldEncrypt, completion: completion)
                } else {
                    let error = ShareMediaError.fileNotFound
                    DDLogError("Upload filed: File not found \(error)")
                    self.callbackQueue.async {
                        completion(nil, error)
                    }
                }
            }*/
        }
    }
    
    /// Currently just a wrapper around sendData
    /*private func upload(media: OTRMediaItem,
                        file: URL,
                        shouldEncrypt: Bool,
                     completion: @escaping (_ url: URL?, _ error: Error?) -> ()) {
        internalQueue.async {
            do {
                let data = try Data(contentsOf: file)
                let mimeType = OTRKitGetMimeTypeForExtension(file.pathExtension)
                self.upload(media: media, data: data, shouldEncrypt: shouldEncrypt, filename: file.lastPathComponent, contentType: mimeType, completion: completion)
            } catch let error {
                DDLogError("Error sending file URL \(file): \(error)")
            }
        }
        
    }*/
    
    private func upload(media: OTRMediaItem,
                        data inData: Data,
                        shouldEncrypt: Bool,
                 filename: String,
                 contentType: String,
                 completion: @escaping (_ url: URL?, _ error: Error?) -> ()) {
        internalQueue.async {
            guard let service = self.servers.first else {
                DDLogWarn("No HTTP upload servers available")
                self.callbackQueue.async {
                    completion(nil, ShareMediaError.noServers)
                }
                return
            }
            var data = inData
            
            // When resending images, sometimes we need to recompress them
            // to fit the max upload limit
            if UInt(data.count) > service.maxSize,
                let _ = media as? OTRImageItem,
                let image = UIImage(data: inData),
                let imageData = image.jpegData(dataSize: .maxBytes(service.maxSize), resize: UIImage.Quality.medium, jpeg: UIImage.Quality.medium, maxTries: 10)
                {
                    data = imageData
            }
            
            if UInt(data.count) > service.maxSize {
                DDLogError("HTTP Upload exceeds max size \(data.count) > \(service.maxSize)")
                self.callbackQueue.async {
                    completion(nil, ShareMediaError.exceedsMaxSize)
                }
                return
            }
            
            // TODO: Refactor to use streaming encryption
            var outData = data
            var outKeyIv: Data? = nil
            if shouldEncrypt {
                guard let key = OTRPasswordGenerator.randomData(withLength: 32), let iv = OTRSignalEncryptionHelper.generateIV() else {
                //guard let key = OTRPasswordGenerator.randomData(withLength: 32), let iv = OTRPasswordGenerator.randomData(withLength: 16) else {
                    DDLogError("Could not generate key/iv")
                    self.callbackQueue.async {
                        completion(nil, ShareMediaError.keyGenerationError)
                    }
                    return
                }
                outKeyIv = iv + key
                do {
                    let crypted = try OTRSignalEncryptionHelper.encryptData(data, key: key, iv: iv)
                    //let crypted = try OTRCryptoUtility.encryptAESGCMData(data, key: key, iv: iv)
                    outData = crypted.data + crypted.authTag
                } catch let error {
                    outData = Data()
                    DDLogError("Could not encrypt data for file transfer \(error)")
                    self.callbackQueue.async {
                        completion(nil, error)
                    }
                    return
                }
            }
            
            self.httpFileUpload.requestSlot(fromService: service.jid, filename: filename, size: UInt(outData.count), contentType: contentType, completion: { (slot: XMPPSlot?, iq: XMPPIQ?, error: Error?) in
                guard let slot = slot else {
                    let outError = error ?? ShareMediaError.serverError
                    DDLogError("\(service) failed to assign upload slot: \(outError)")
                    self.callbackQueue.async {
                        completion(nil, outError)
                    }
                    return
                }
                
                self.sessionManager.upload(outData, to: slot.putURL, method: .put)
                    .validate()
                    .response(queue: self.callbackQueue) { response in
                        switch response.result {
                        case .success:
                            if let outKeyIv = outKeyIv {
                                // If there's a AES-GCM key, we gotta put it in the url
                                // and change the scheme to `aesgcm`
                                if var components = URLComponents(url: slot.getURL, resolvingAgainstBaseURL: true) {
                                    components.scheme = URLScheme.aesgcm.rawValue
                                    components.fragment = outKeyIv.toHexString()
                                    if let outURL = components.url {
                                        completion(outURL, nil)
                                    } else {
                                        completion(nil, ShareMediaError.urlFormatting)
                                    }
                                } else {
                                    completion(nil, ShareMediaError.urlFormatting)
                                }
                            } else {
                                // The plaintext case
                                completion(slot.getURL, nil)
                            }
                        case .failure(let error):
                            completion(nil, error)
                            DDLogError("Upload error: \(error)")
                        }
                    }.uploadProgress(queue: self.internalQueue) { progress in
                        //DDLogVerbose("Upload progress \(progress.fractionCompleted)")
                        self.connection?.asyncReadWrite { transaction in
                            if let media = media.refetch(with: transaction) {
                                media.transferProgress = Float(progress.fractionCompleted)
                                media.save(with: transaction)
                                media.touchParentMessage(with: transaction)
                            }
                        }
                }
            })
        }
    }
    
    /*@objc public func send(videoURL url: URL, thread: OTRThreadOwner) {
        internalQueue.async {
            self.send(url: url, thread: thread, type: .video)
        }
    }*/
    
    /*private enum MediaURLType {
        case audio
        case video
        case file
    }*/
    
    /*private func send(url: URL, thread: OTRThreadOwner, type: MediaURLType) {
        internalQueue.async {
            var item: OTRMediaItem? = nil
            switch type {
            case .audio:
                item = OTRAudioItem(audioURL: url, isIncoming: false)
            case .video:
                item = OTRVideoItem(videoURL: url, isIncoming: false)
            case .file:
                item = OTRFileItem(fileURL: url, isIncoming: false)
            }
            guard let mediaItem = item else {
                DDLogError("No media item to share for URL: \(url)")
                return
            }
            
            guard let message = self.newOutgoingMessage(to: thread, mediaItem: mediaItem) else {
                DDLogError("No message could be created for \(thread) \(mediaItem)")
                return
            }
            mediaItem.parentObjectKey = message.messageKey
            mediaItem.parentObjectCollection = message.messageCollection
            let newPath = OTRMediaFileManager.path(for: mediaItem, buddyUniqueId: thread.threadIdentifier)
            self.connection.readWrite { transaction in
                message.save(with: transaction)
                mediaItem.save(with: transaction)
                
            }
            OTRMediaFileManager.shared.copyData(fromFilePath: url.path, toEncryptedPath: newPath, completion: { (result, copyError: Error?) in
                var prefetchedData: Data? = nil
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        if let size = attributes[FileAttributeKey.size] as? NSNumber, size.uint64Value < 1024 * 1024 * 100 {
                            prefetchedData = try Data(contentsOf: url)
                        }
                    } catch let error {
                        DDLogError("Error prefetching data: \(error)")
                    }
                    do {
                        try FileManager.default.removeItem(atPath: url.path)
                    } catch let error {
                        DDLogError("Error removing file: \(error)")
                    }
                }
                message.messageError = copyError
                self.connection.readWrite({ (transaction) in
                    mediaItem.save(with: transaction)
                    message.save(with: transaction)
                })
                self.send(mediaItem: mediaItem, prefetchedData: prefetchedData, message: message)
            }, completionQueue: self.internalQueue)
        }
    }*/
    
    /*@objc public func send(audioURL url: URL, thread: OTRThreadOwner) {
        internalQueue.async {
            self.send(url: url, thread: thread, type: .audio)
        }
    }*/
    
    @objc public func send(image: UIImage, thread: OTRThreadOwner) {
        internalQueue.async {
            guard let service = self.servers.first, service.maxSize > 0 else {
                DDLogError("No HTTP upload service available!")
                return
            }
            let filename = "\(UUID().uuidString).jpg"
            let imageItem = OTRImageItem(filename: filename, size: image.size, mimeType: "image/jpeg", isIncoming: false)
            guard let message = self.newOutgoingMessage(to: thread, mediaItem: imageItem) else {
                DDLogError("No message could be created")
                return
            }
            imageItem.parentObjectKey = message.messageKey
            imageItem.parentObjectCollection = message.messageCollection
            self.connection?.readWrite { transaction in
                message.save(with: transaction)
                imageItem.save(with: transaction)
            }
            
            guard let ourImageData = image.jpegData(dataSize: .unlimited, resize: UIImage.Quality.low, jpeg: UIImage.Quality.low, maxTries: 10) else {
                DDLogError("Could not make JPEG out of image!")
                return
            }
            OTRMediaFileManager.shared.setData(ourImageData, for: imageItem, buddyUniqueId: thread.threadIdentifier, completion: { (bytesWritten: Int, error: Error?) in
                self.connection?.readWrite({ (transaction) in
                    imageItem.touchParentMessage(with: transaction)
                    if let error = error {
                        message.messageError = error
                        message.save(with: transaction)
                    }
                })
                if let imageData = image.jpegData(dataSize: .maxBytes(service.maxSize), resize: UIImage.Quality.medium, jpeg: UIImage.Quality.medium, maxTries: 10) {
                    self.send(mediaItem: imageItem, prefetchedData: imageData, message: message)
                } else {
                    DDLogError("Could not make JPEG out of image! Bad size")
                    message.messageError = ShareMediaError.exceedsMaxSize
                    self.connection?.readWrite { transaction in
                        message.save(with: transaction)
                    }
                }
            }, completionQueue: self.internalQueue)
        }
    }
    
    /*@objc public func send(fileURL url: URL, thread: OTRThreadOwner) {
        internalQueue.async {
            self.send(url: url, thread: thread, type: .file)
        }
    }*/
    
    private func newOutgoingMessage(to thread: OTRThreadOwner, mediaItem: OTRMediaItem) -> OTRMessageProtocol? {
        if let buddy = thread as? OTRBuddy {
            let message = OTROutgoingMessage()!
            var security: OTRMessageTransportSecurity = .invalid
            self.connection?.read({ (transaction) in
                security = buddy.preferredTransportSecurity(with: transaction)
            })
            message.buddyUniqueId = buddy.uniqueId
            message.mediaItemUniqueId = mediaItem.uniqueId
            message.messageSecurityInfo = OTRMessageEncryptionInfo(messageSecurity: security)

            //let gtimer = OTRSettingsManager.string(forOTRSettingKey: "globalTimer")
            if (thread.expiresIn != nil) {
                message.expires = thread.expiresIn
            }
            return message
        } else if let room = thread as? OTRXMPPRoom {
            var message:OTRXMPPRoomMessage? = nil
            self.connection?.read({ (transaction) in
                message = room.outgoingMessage(withText: "", transaction: transaction) as? OTRXMPPRoomMessage
            })
            if let message = message {
                message.messageText = nil
                message.mediaItemId = mediaItem.uniqueId
                //We are NOT checking for existing keys, just assuming
                message.messageSecurityInfo = OTRMessageEncryptionInfo(messageSecurity: .OMEMO)
            }
            return message
        }
        return nil
    }
    
    @objc public func send(mediaItem: OTRMediaItem, prefetchedData: Data?, message: OTRMessageProtocol) {
        var shouldEncrypt = false
        switch message.messageSecurity {
        case .OMEMO, .OTR:
            shouldEncrypt = true
        case .invalid, .plaintext, .plaintextWithOTR:
            shouldEncrypt = false
        }
        
        self.upload(mediaItem: mediaItem, shouldEncrypt: shouldEncrypt, prefetchedData: prefetchedData, completion: { (_url: URL?, error: Error?) in
            guard let url = _url else {
                if let error = error {
                    DDLogError("Error uploading: \(error)")
                }
                self.connection?.readWrite({ (transaction) in
                    message.messageError = error
                    message.save(with: transaction)
                })
                self.shareDelegate.doShare(nil)
                return
            }
            self.connection?.readWrite({ (transaction) in
                mediaItem.transferProgress = 1.0
                message.messageText = url.absoluteString
                mediaItem.save(with: transaction)
                message.save(with: transaction)
            })
            
            self.shareDelegate.doShare(message)
            //self.queueOutgoingMessage(message: message)
        })
    }
    
    
    // MARK: - Private Methods
    
    private func serversFromCapabilities(capabilities: [XMPPJID : XMLElement]) -> [HTTPServer] {
        var servers: [HTTPServer] = []
        for (jid, element) in capabilities {
            let supported = element.supportsHTTPUpload()
            let maxSize = element.maxHTTPUploadSize()
            if supported && maxSize > 0 {
                let server = HTTPServer(jid: jid, maxSize: maxSize)
                servers.append(server)
            }
        }
        return servers
    }
}

public extension OTRMessageProtocol {
    var downloadableURLs: [URL] {
        return self.messageText?.downloadableURLs ?? []
    }
}

public extension OTRBaseMessage {
    @objc var downloadableNSURLs: [NSURL] {
        return self.downloadableURLs as [NSURL]
    }
}

public extension OTRXMPPRoomMessage {
    @objc var downloadableNSURLs: [NSURL] {
        return self.downloadableURLs as [NSURL]
    }
}

// MARK: - Extensions

fileprivate struct HTTPServer {
    /// service jid for upload service
    let jid: XMPPJID
    /// max upload size in bytes
    let maxSize: UInt
}

public extension XMLElement {
    
    // For use on a <query> element
    func supportsHTTPUpload() -> Bool {
        let features = self.elements(forName: "feature")
        var supported = false
        for feature in features {
            if let value = feature.attributeStringValue(forName: "var"),
                value == XMPPHTTPFileUploadNamespace  {
                supported = true
                break
            }
        }
        return supported
    }
    
    /// Returns 0 on failure, or max file size in bytes
    func maxHTTPUploadSize() -> UInt {
        var maxSize: UInt = 0
        let xes = self.elements(forXmlns: "jabber:x:data")
        
        for x in xes {
            let fields = x.elements(forName: "field")
            var correctXEP = false
            for field in fields {
                if let value = field.element(forName: "value") {
                    if value.stringValue == XMPPHTTPFileUploadNamespace {
                        correctXEP = true
                    }
                    if let varMaxFileSize = field.attributeStringValue(forName: "var"), varMaxFileSize == "max-file-size" {
                        maxSize = value.stringValueAsNSUInteger()
                    }
                }
            }
            if correctXEP && maxSize > 0 {
                break
            }
        }
        
        return maxSize
    }
}

// expand to http?
enum URLScheme: String {
    case https = "https"
    case aesgcm = "aesgcm"
    static let downloadableSchemes: [URLScheme] = [.https, .aesgcm]
}

extension URL {
    
    /** URL scheme matches aesgcm:// */
    var isAesGcm: Bool {
        return scheme == URLScheme.aesgcm.rawValue
    }
    
    /** Has hex anchor with key and IV. 48 bytes w/ 16 iv + 32 key */
    var anchorData: Data? {
        guard let anchor = self.fragment else { return nil }
        let data = anchor.dataFromHex()
        return data
    }
    
    var aesGcmKey: (key: Data, iv: Data)? {
        guard let data = self.anchorData else { return nil }
        let ivLength: Int
        switch data.count {
        case 48:
            // legacy clients send 16-byte IVs
            ivLength = 16
        case 44:
            // newer clients send 12-byte IVs
            ivLength = 12
        default:
            return nil
        }
        let iv = data.subdata(in: 0..<ivLength)
        let key = data.subdata(in: ivLength..<data.count)
        
        return (key, iv)
    }
}

public extension NSString {
    var isSingleURLOnly: Bool {
        return (self as String).isSingleURLOnly
    }
}

public extension String {
    
    private var urlRanges: ([URL], [NSRange]) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return ([], [])
        }
        var urls: [URL] = []
        var ranges: [NSRange] = []
        
        let matches = detector.matches(in: self, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSRange(location: 0, length: self.utf16.count))
        
        for match in matches where match.resultType == .link {
            if let url = match.url {
                urls.append(url)
                ranges.append(match.range)
            }
        }
        return (urls, ranges)
    }
    
    /** Grab any URLs from a string */
    var urls: [URL] {
        let (urls, _) = urlRanges
        return urls
    }
    
    /** Returns true if the message is ONLY a single URL */
    var isSingleURLOnly: Bool {
        let (_, ranges) = urlRanges
        guard ranges.count == 1,
            let range = ranges.first,
            range.length == self.count else {
            return false
        }
        return true
    }
    
    /** Use this for extracting potentially downloadable URLs from a message. Currently checks for https:// and aesgcm:// */
    var downloadableURLs: [URL] {
        
        return urlsMatchingSchemes(URLScheme.downloadableSchemes)
    }
    
    fileprivate func urlsMatchingSchemes(_ schemes: [URLScheme]) -> [URL] {
        let urls = self.urls.filter {
            guard let scheme = $0.scheme?.lowercased() else { return false }
            for inScheme in schemes where inScheme.rawValue == scheme {
                return true
            }
            return false
        }
        return urls
    }
}

public extension ShareMediaManager {
    /// Returns whether or not message should be displayed or hidden from collection. Single incoming URLs should be hidden, for example.
    @objc static func shouldDisplayMessage(_ message: OTRMessageProtocol, transaction: YapDatabaseReadTransaction) -> Bool {
        // Always show media messages
        if message.messageMediaItemKey != nil {
            return true
        }
        // Always show downloads
        if message is OTRDownloadMessage {
            return true
        }
        // Hide non-media messages that have no text
        guard let messageText = message.messageText else {
            return false
        }
        
        // Filter out messages that are aesgcm scheme file transfers
        if messageText.contains("aesgcm://"),
            message.messageError == nil {
            return false
        }
        
        // Filter out messages that are just URLs and have downloads
        if messageText.isSingleURLOnly,
            message.hasExistingDownloads(with: transaction) {
            return false
        }
        
        // so media messages don't show as link in group, maybe remove after OMEMO
        if messageText.isSingleURLOnly,
           message.downloads().count > 0, message.isMessageIncomingOrDifferentDevice { 
            return false
        }

        return true
    }
}

