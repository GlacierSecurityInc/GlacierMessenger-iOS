//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Scott Fister on 4/24/17.
//  Copyright © 2017 Scott Fister. All rights reserved.
//
import UIKit
import Social
import MobileCoreServices
import MBProgressHUD
import LinkPresentation

@available(iOSApplicationExtension 13.0, *)
class ShareViewController: SLComposeServiceViewController, ShareExtensionDelegate {
    
    //private var url: NSURL?
    private var userConversations = [Conversation]()
    fileprivate var selectedConversation: Conversation?
    private var dataInterface: GlacierShareDataInterface?
    
    private var shareurl: URL?
    private var urlString: String?
    private var textString: String?
    private var finalText: String?
    private var isText:Bool = false
    private var pagetitle:String?
    private var mediaType: MediaURLType?
    private var mediaReady: Bool = false
    private var provider = LPMetadataProvider()
    private var sharectr: Int = 0
    private var hud:MBProgressHUD?
    //private var disGroup:DispatchGroup?
    //private var linkView = LPLinkView()
    
    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        if urlString != nil || textString != nil {
            if !contentText.isEmpty {
                return true
            }
        }
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        //init database
        if (self.dataInterface == nil) {
            self.dataInterface = GlacierShareDataInterface(delegate: self)
        }
        
        getURL()
        
        hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.userConversations = self.dataInterface?.getAllConversations() as! [Conversation]
            self.selectedConversation = self.userConversations.first
            self.reloadConfigurationItems()
            self.hud?.removeFromSuperview()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let slSheet = self.childViewControllers.first as? UINavigationController,
           let tblView = slSheet.childViewControllers.first?.view.subviews.first as? UITableView
        {
            // Scroll tablView to bottom
            tblView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .bottom, animated: true)
        }
    }
    
    override func loadPreviewView() -> UIView! {
        var previewView = super.loadPreviewView()
        if (previewView == nil && !isText) { 
            //return self.linkView
            if let glacierImage = UIImage(named: "Safari", in: GlacierInfo.resourcesBundle, compatibleWith: nil) {
                var image = glacierImage
                //if #available(iOSApplicationExtension 13.0, *) {
                    image = glacierImage.withTintColor(UIColor.label)
                //}
                previewView = UIImageView(image: image)
                previewView?.contentMode = .scaleAspectFit
            }
        }
        
        return previewView
    }
    
    deinit {
        // perform the deinitialization
        self.dataInterface?.teardownStream()
        self.dataInterface = nil
    }
    
    private func setupUI() {
        if let glacierImage = UIImage(named: "glacier", in: GlacierInfo.resourcesBundle, compatibleWith: nil) {
            var image = glacierImage
            //if #available(iOSApplicationExtension 13.0, *) {
                image = glacierImage.withTintColor(UIColor.label)
            //}
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            navigationItem.titleView = imageView
            navigationController?.navigationBar.topItem?.titleView = imageView
        }
        
        var tColor = UIColor.black
        //if #available(iOSApplicationExtension 13.0, *) {
            tColor = UIColor.label
        //}
        navigationController?.navigationBar.tintColor = tColor
        navigationController?.navigationBar.backgroundColor = UIColor(hue: 210.0/360.0, saturation: 0.94, brightness: 1.0, alpha: 1.0)
    }
    
    @objc public enum MediaURLType:Int {
        case audio
        case video
        case file
        case image
        case url
    }
    
    private func getURL() {
        let extensionItem = extensionContext?.inputItems.first as! NSExtensionItem

        for attachment in extensionItem.attachments as! [NSItemProvider] {
            /*if attachment.isFile {
                attachment.loadItem(forTypeIdentifier:kUTTypeFileURL as String, options: nil, completionHandler: { (results, error) in
                    if let url = results as! URL? {
                        self.readyMedia(url, type: .file)
                    }
                })
            } else if attachment.isVideo {
                attachment.loadItem(forTypeIdentifier:kUTTypeMovie as String, options: nil, completionHandler: { (results, error) in
                    if let url = results as! URL? {
                        self.readyMedia(url, type: .video)
                    }
                })
            } else*/
            if attachment.isPropertyList {
                attachment.loadItem(forTypeIdentifier:kUTTypePropertyList as String, options: nil, completionHandler: { (results, error) -> Void in
                    guard let dictionary = results as? NSDictionary else { return }
                    OperationQueue.main.addOperation {
                        if let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                            let urlStr = results["URL"] as? String,
                            let url = URL(string: urlStr) {
                                self.textString = url.absoluteString
                                self.urlString = url.absoluteString
                                self.getLinkPreview(url)
                        }
                    }
                })
            } else if attachment.isImage {
                attachment.loadItem(forTypeIdentifier:kUTTypeImage as String, options: nil, completionHandler: { (results, error) in
                    if let url = results as! URL? {
                        self.readyMedia(url, type: .image)
                    }
                })
            } else if attachment.isURL {
                attachment.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (results, error) in
                    if let url = results as! URL? {
                        self.textString = url.absoluteString
                        self.urlString = url.absoluteString
                        self.getLinkPreview(url)
                    }
                })
            } else if attachment.isText {
                self.isText = true
                attachment.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil, completionHandler: { (results, error) in
                    let text = results as! String
                    self.textString = text
                    //_ = self.isContentValid()
                })
            }
        }
    }
    
    private func getLinkPreview(_ url:URL) {
        
        //self.linkView.removeFromSuperview()
        //self.linkView = LPLinkView(url: url)
        
        DispatchQueue.main.async{ [weak self] in
            guard let self = self else { return }
            self.provider = LPMetadataProvider()
            self.provider.startFetchingMetadata(for: url) { metadata, error in
                guard let metadata = metadata, error == nil  else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if (self.textView.text.count == 0) {
                        self.textView.text = metadata.title
                        self.pagetitle = metadata.title
                    } else {
                        self.pagetitle = self.textView.text
                    }
                }
            }
        }
    }
    
    private func readyMedia(_ url:URL, type:MediaURLType) {
        self.shareurl = url
        self.urlString = url.absoluteString
        self.mediaType = type
        
        if (self.mediaType != nil && self.shareurl != nil && !mediaReady) {
            mediaReady = true
            dataInterface?.setupMediaManager()
        }
    }
    
    //the user actually clicks post
    override func didSelectPost() {
        guard let tOwner = selectedConversation?.owner else {
            return
        }
        
        if let moretext = self.contentText, moretext.count > 1 {
            if self.pagetitle != nil && moretext != self.pagetitle {
                self.finalText = moretext
            } else if self.pagetitle == nil {
                self.finalText = moretext
            }
        }
        
        //disGroup = DispatchGroup()
        sharectr = 1
        self.hud = nil
        
        //Use the existing stored info?
        if let mediatype = self.mediaType, let url = self.shareurl {
            self.hud = MBProgressHUD.showAdded(to: self.view, animated: true)
            self.dataInterface?.doShare(url, with: tOwner, withType: mediatype.rawValue)
            if let extraText = self.finalText {
                sharectr=2
                self.dataInterface?.doShare(extraText, with: tOwner)
            }
        } else if let textstring = self.finalText { //self.textString {
            self.hud = MBProgressHUD.showAdded(to: self.view, animated: true)
            if let linkText = self.urlString {
                sharectr=2
                self.dataInterface?.doShare(linkText, with: tOwner)
            }
            self.dataInterface?.doShare(textstring, with: tOwner)
        } else if let linkText = self.urlString {
            self.hud = MBProgressHUD.showAdded(to: self.view, animated: true)
            self.dataInterface?.doShare(linkText, with: tOwner)
        } else {
            self.doneSending(false)
        }
        
        /*if let url = data as? URL, let imageData = try? Data(contentsOf: url) {
            //self.save(imageData, key: "imageData", value: imageData)
        } else if let img = data as? UIImage{
            imgData = UIImagePNGRepresentation(img)
        } else {
            // Handle this situation as you prefer
            fatalError("Impossible to save image")
        }*/
    }
    
    func doneSending(_ success:Bool) {
        if !success {
            self.hud?.removeFromSuperview()
            let alert = UIAlertController(title: "Share Failed", message: "Unable to send message. Please try again.", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "OK", style: .cancel) {
                (result : UIAlertAction) -> Void in
                self.dataInterface?.teardownStream()
                self.dataInterface = nil
                self.userConversations.removeAll()
                self.selectedConversation = nil
                self.extensionContext?.completeRequest(returningItems: [], completionHandler:nil)
            }
            alert.addAction(cancelAction)
            present(alert, animated: true, completion: nil)
            return
        }
        //_ = [ NSExtensionJavaScriptFinalizeArgumentKey : [ "statusMessage" : "Done Sending" ]]
        
        if (sharectr > 1) {
            sharectr = sharectr-1
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.dataInterface?.teardownStream()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.dataInterface = nil
                self.userConversations.removeAll()
                self.selectedConversation = nil
                self.hud?.removeFromSuperview()
                self.extensionContext?.completeRequest(returningItems: [], completionHandler:nil)
            }
        }
    }

    //get options for conversations to add it to...this is my Glacier interface
    override func configurationItems() -> [Any]! {
        if let conversation = SLComposeSheetConfigurationItem() {
            conversation.title = "To:"
            conversation.value = selectedConversation?.name
            conversation.tapHandler = {
                let vc = ShareSelectViewController()
                vc.userConversations = self.userConversations
                vc.delegate = self
                self.pushConfigurationViewController(vc)
            }
            return [conversation]
        }
        return nil
    }
}

@available(iOSApplicationExtension 13.0, *)
extension ShareViewController: ShareSelectViewControllerDelegate {
    func selected(conversation: Conversation) {
        selectedConversation = conversation
        reloadConfigurationItems()
        popConfigurationViewController()
    }
}

extension NSItemProvider {
    
    var isURL: Bool {
        return hasItemConformingToTypeIdentifier(kUTTypeURL as String)
    }
    
    var isText: Bool {
        return hasItemConformingToTypeIdentifier(kUTTypeText as String)
    }
    
    var isImage: Bool {
        return hasItemConformingToTypeIdentifier(kUTTypeImage as String)
    }
    
    /*var isVideo: Bool {
        return hasItemConformingToTypeIdentifier(kUTTypeMovie as String)
    }
    
    var isFile: Bool {
        return hasItemConformingToTypeIdentifier(kUTTypeFileURL as String)
    }*/
    
    var isPropertyList:Bool {
        return hasItemConformingToTypeIdentifier(kUTTypePropertyList as String)
    }
}

/*@objc(CustomShareNavigationController)
class ShareNavigationController: UINavigationController {

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        // 2: set the ViewControllers
        self.setViewControllers([ShareViewController()], animated: false)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}*/
