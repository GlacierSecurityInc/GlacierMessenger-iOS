//
//  RoomAttachmentWebViewController.swift
//  ChatSecureCore
//
//  Created by Andy Friedman on 5/13/19.
//  Copyright © 2019 GlacierSecurity. All rights reserved.

import UIKit
import WebKit
import OTRAssets
open class RoomAttachmentWebViewController: UIViewController, WKUIDelegate {
    
    var webView: WKWebView!
    var attachUrl: URL
    var attachData: Data?
    var baseUrl: URL
    
    var saveUrl: URL
    var saving: Bool
    
    @objc public init(url:URL, data:Data?, baseurl:URL) {
        attachUrl = url
        saveUrl = attachUrl
        attachData = data
        baseUrl = baseurl
        saving = false
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.uiDelegate = self
        view = webView
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        if let data = attachData {
            let contentType = OTRKitGetMimeTypeForExtension(attachUrl.pathExtension)
            webView.load(data, mimeType: contentType, characterEncodingName: "UTF-8", baseURL: baseUrl)
        } else {
            if (attachUrl.isFileURL) {
                webView.loadFileURL(attachUrl, allowingReadAccessTo: attachUrl)
            } else {
                let myRequest = URLRequest(url: attachUrl)
                webView.load(myRequest)
            }
        }
        
        saving = false
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveFile(_:)))
        self.navigationItem.rightBarButtonItem = saveButton
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if (saving) {
            return
        }
        
        if (attachUrl.isFileURL) {
            do {
                try FileManager.default.removeItem(at: attachUrl)
            } catch {
                print("Could not delete local file: \(error)")
            }
        } else if (saveUrl.isFileURL) {
            do {
                try FileManager.default.removeItem(at: saveUrl)
            } catch {
                print("Could not delete local file: \(error)")
            }
        }
        
        attachData = nil
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        saving = false
    }
    
    @objc private func saveFile(_ sender: Any) {
        saving = true
        
        saveUrl = attachUrl
        if (!attachUrl.isFileURL) {
            if let storedUrl = self.tryStoreLocal() {
                saveUrl = storedUrl
            }
        }
        
        if (saveUrl.isFileURL) {
            let activityViewController = UIActivityViewController(activityItems: [saveUrl], applicationActivities: nil)
            activityViewController.completionWithItemsHandler = { (activity, success, items, error) in
                if (success) {
                    let msg = self.saveUrl.lastPathComponent + " has been saved!"
                    let alert = UIAlertController(title: "File Saved", message: msg, preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                } else if (error != nil) {
                    self.saveAlert()
                }
            }
            self.present(activityViewController, animated: true, completion: nil)
        } else {
            saveAlert()
        }
    }
    
    private func tryStoreLocal() -> URL? {
        
        if (attachData == nil) {
            do {
                attachData = try Data(contentsOf: attachUrl)
            } catch {
                // contents could not be loaded
                saveAlert()
                return nil
            }
            
            if (attachData == nil) {
                saveAlert()
                return nil
            }
        }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileurl = paths[0].appendingPathComponent(attachUrl.lastPathComponent)
        
        do {
            try attachData!.write(to: fileurl, options: .atomic)//, encoding: String.Encoding.utf8)
        } catch {
            // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
            DDLogError("Something went wrong storing data locally")
            saveAlert()
            return nil
        }
        
        return fileurl
    }
    
    private func saveAlert() {
        let alert = UIAlertController(title: "Cannot Save", message: "There is a problem trying to save this file", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: UIAlertActionStyle.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}
