//
//  CallManager.swift
//  Created by Andy Friedman on 2/10/20.
//  Copyright © 2020 Glacier Security. All rights reserved.

import Foundation
import XMPPFramework
import CallKit
import TwilioVideo
import AVFoundation

@objc public protocol TwilioCallDelegateProtocol:NSObjectProtocol {
    //func activateAudio(_ activate: Bool)
    func holdCall(_ onHold: Bool)
    func muteAudio(_ isMuted: Bool)
    func disconnectCall(_ userInitiated: Bool)
    func turnOnVideo()
    func isConnected() -> Bool
    func setStatus(_ status:String)
    func setBluetoothEnabled(_ bluetoothEnabled: Bool)
    func handleAudioDenied()
}

public enum SpeakerChoice : UInt {
    case receiver = 0
    case speaker = 1
    case bluetooth = 2
}

/**
 * The purpose of this class is to collect and process server
 * and push info in one place.
 *
 * All public members must be accessed from the main queue.
 */
public class CallManager: XMPPModule {
    private static let shared = CallManager(dispatchQueue: nil)
    
    @objc public static let XMPPCommandNamespace = "http://jabber.org/protocol/commands"
    @objc public static let CallManagerErrorDomain = "CallManagerErrorDomain"
    var tracker:XMPPIDTracker?
    var cAccount:OTRXMPPAccount?
    var currentCall:TwilioCall?
    var currentUuid:UUID?
    var awaitingCallResponse:Bool = false
    var waitingToAnswerCall:Bool = false
    var waitingToRespondBusy:Bool = false
    var waitingToRespondReject:Bool = false
    var isBusy:Bool = false
    var busyTone:Bool = false
    var busyId:NSNumber?
    
    var bluetoothAvailable: Bool = false
    var bluetoothEnabled: Bool = false
    var speakerChoice: SpeakerChoice = SpeakerChoice.receiver
    
    @objc private weak var tdelegate:TwilioCallDelegateProtocol? = nil
    
    // CallKit components
    let callKitProvider: CXProvider
    let callKitCallController: CXCallController
    var userInitiatedDisconnect: Bool = false
    
    var callTimeout: DispatchWorkItem?
    
    var player: AVAudioPlayer?
    
    /**
     * We will create an audio device and manage it's lifecycle in response to CallKit events.
     */
    var audioDevice: DefaultAudioDevice = DefaultAudioDevice()

    deinit {
        // CallKit has an odd API...must call invalidate or the CXProvider is leaked.
        callKitProvider.invalidate()
        
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private override init(dispatchQueue: DispatchQueue? = nil) {
        self.cAccount = nil
        
        let configuration = CXProviderConfiguration(localizedName: "Glacier")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        //configuration.ringtoneSound = "MarimbaRingtone.wav"
        configuration.supportsVideo = true
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false;
        if let callKitIcon = UIImage(named: "glacier", in: GlacierInfo.resourcesBundle, compatibleWith: nil) {
            configuration.iconTemplateImageData = UIImagePNGRepresentation(callKitIcon)
        }
        callKitProvider = CXProvider(configuration: configuration)
        callKitCallController = CXCallController()
        
        super.init(dispatchQueue: dispatchQueue)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleLoginSuccess), name: NSNotification.Name(rawValue: kOTRProtocolLoginSuccess), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChange(_:)), name: NSNotification.Name(rawValue: NSNotification.Name.AVAudioSessionRouteChange.rawValue), object: nil)
        
        callKitProvider.setDelegate(self, queue: nil)
        
        self.audioDevice.block = {
            do {
                DefaultAudioDevice.DefaultAVAudioSessionConfigurationBlock()
                let audioSession = AVAudioSession.sharedInstance()
                
                try audioSession.setMode(AVAudioSessionModeVoiceChat)
                try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                
            } catch {
                DDLogError("Twilio audio Fail: \(error.localizedDescription)")
            }
        }
        
        TwilioVideoSDK.audioDevice = self.audioDevice;
        
        self.audioDevice.block();
    }
    
    @objc public class func sharedCallManager() -> CallManager {
        return shared
    }
    
    @objc public func setAccount(_ account: OTRXMPPAccount) {
        self.cAccount = account
    }
    
    @objc public func hasAccount() -> Bool {
        if (self.cAccount != nil) {return true}
        
        return false
    }
    
    @objc public func setTwilioDelegate(_ del: TwilioCallDelegateProtocol) {
        self.tdelegate = del
    }

    public func getCallBuddy(_ identity: String) -> OTRBuddy? {
        var bud:OTRBuddy?
        if let jid = XMPPJID(string: identity), let acct = self.cAccount {
            OTRDatabaseManager.shared.readConnection?.read { (transaction) in
                bud = OTRXMPPBuddy.fetchBuddy(jid: jid, accountUniqueId: acct.uniqueId, transaction: transaction) 
            }
        }
        return bud
    }
    
    @discardableResult override public func activate(_ xmppStream: XMPPStream) -> Bool {
        if super.activate(xmppStream) {
            self.performBlock {
                self.tracker = XMPPIDTracker.init(stream: xmppStream, dispatchQueue: self.moduleQueue)
            }
        } else {
            return false
        }
        return true
    }
    
    public override func deactivate() {
        self.performBlock {
            self.tracker?.removeAllIDs()
            self.tracker = nil
            self.callTimeout?.cancel()
        }
        tdelegate = nil
        super.deactivate()
    }
    
    // MARK: Public API
    
    /**
     * <iq from='hag66@shakespeare.lit/pda' id='h7ns81g' to='p2.glaciersec.cc' type='set'>
     *   <command xmlns='http://jabber.org/protocol/commands' action='execute' node='call-user-apns'>
     *     <x xmlns="jabber:x:data" type="submit">
     *       <field var="caller"><value>hag66</value></field>
     *       <field var="callerdevice"><value>152F11D4-9380-43E4-BCDE-B47314752B9B</value></field>
     *       <field var="receiver"><value>joe12@shakespeare.lit</value></field>
     *       <field var="roomname"><value>uih2345</value></field>
     *     </x>
     *   </command>
     * </iq>
     * Note: caller is a display name, but receiver is the bare JID of the receiver
     */
    @objc public func makeCall(_ receivers: [String], name: String)
    {
        let call = TwilioCall()
        call.calltitle = name
        
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        let caller = self.cAccount?.displayName
        
        // don't need to do this, it gets created on server if none provided
        let roomname = OTRRoomNames.getRoomName()
        call.roomname = roomname
        self.currentUuid = UUID.init()
        call.callUuid = self.currentUuid
        self.currentCall = call
        
        //call CallKit here before sending to ejabberd
        if let uuid = self.currentUuid {
            performStartCallAction(uuid: uuid, receiver: name) //receiver)
        }
        
        // This is a public method, so it may be invoked on any thread/queue.
        self.performBlock(async: true){
            //let queryElement = try! XMLElement(xmlString: queryString)
            let command = XMLElement(name: "command", xmlns: CallManager.XMPPCommandNamespace)
            command.addAttribute(withName: "action", stringValue: "execute")
            command.addAttribute(withName: "node", stringValue: "call-user-apns")
            let x = XMLElement(name: "x", xmlns: "jabber:x:data")
            x.addAttribute(withName: "type", stringValue: "submit")
            
            let callerfield = XMLElement(name: "field")
            callerfield.addAttribute(withName: "var", stringValue: "caller")
            let callerval = XMLElement(name: "value", stringValue: caller)
            callerfield.addChild(callerval)
            
            let devicefield = XMLElement(name: "field")
            devicefield.addAttribute(withName: "var", stringValue: "callerdevice")
            let deviceval = XMLElement(name: "value", stringValue: deviceId)
            devicefield.addChild(deviceval)
            
            let receiverfield = XMLElement(name: "field")
            receiverfield.addAttribute(withName: "var", stringValue: "receiver")
            
            for callbuddy in receivers {
                let receiverval = XMLElement(name: "value", stringValue: callbuddy)
                receiverfield.addChild(receiverval)
            }
            let titlefield = XMLElement(name: "field")
            titlefield.addAttribute(withName: "var", stringValue: "title")
            let titleval = XMLElement(name: "value", stringValue: name)
            titlefield.addChild(titleval)
            
            let roomfield = XMLElement(name: "field")
            roomfield.addAttribute(withName: "var", stringValue: "roomname")
            let roomval = XMLElement(name: "value", stringValue: roomname)
            roomfield.addChild(roomval)
            
            x.addChild(callerfield)
            x.addChild(devicefield)
            x.addChild(receiverfield)
            x.addChild(roomfield)
            x.addChild(titlefield)
            
            command.addChild(x)
            let tojid = XMPPJID(string: "p2." + GlacierInfo.defaultHost())
            let iq = XMPPIQ.init(iqType: XMPPIQ.IQType.set, to: tojid, elementID: self.xmppStream?.generateUUID, child: command)
            iq.addAttribute(withName: "from", stringValue: (self.xmppStream?.myJID?.full ?? caller)!)
            
            self.tracker?.add(iq, target: self, selector: #selector(self.handleMakeCallResponse(_:)), timeout: 15)
            
            self.xmppStream?.send(iq)
        }
    }
    
    @objc private func handleMakeCallResponse(_ iq: XMPPIQ) {
        let x = iq.childElement?.element(forName: "x", xmlns: "jabber:x:data")
        guard let fields = x?.elements(forName: "field") else {
            //handle failed case, alert user
            performCancelCallAction(userInitiated: false)
            
            var name = ""
            if let names = self.currentCall?.receiver?.components(separatedBy: ",") {
                for rec in names {
                    name = name + rec.components(separatedBy: "@")[0]
                }
            }
            if (name.count == 0) {
                name = "the other user(s)"
            }
            
            //let name = self.currentCall?.receiver?.components(separatedBy: "@")[0]
            //let user = name ?? "the other user(s)"
            let alert = UIAlertController(title: "Call Failed", message: "Your call could not be connected. Please make sure \(name) has opened Glacier at least once after logging in and if the problem continues contact Glacier Support.", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
            alert.addAction(cancelAction)
            DispatchQueue.main.async {
                OTRAppDelegate.appDelegate.messagesViewController.present(alert, animated: true, completion: nil)
            }
            return
        }
        let call = TwilioCall()
        for field in fields {
            if let fvar = field.attributeStringValue(forName: "var"), let fval = field.element(forName: "value")?.stringValue {
                if fvar == "caller" {
                    call.caller = fval
                } else if fvar == "receiver" {
                    call.receiver = fval
                } else if fvar == "room_name" {
                    call.roomname = fval
                } else if fvar == "token" {
                    call.token = fval
                } else if fvar == "call_id" {
                    if let number = NumberFormatter().number(from: fval) {
                        call.callid = number
                    }
                }
            }
        }
        if let title = self.currentCall?.calltitle {
            call.calltitle = title
        } else {
            call.calltitle = call.receiver?.components(separatedBy: "@")[0]
        }
        call.callUuid = self.currentUuid
        call.outgoing = true
        self.currentCall = call
        
        DispatchQueue.main.async {
            OTRAppDelegate.appDelegate.conversationViewController.openCall(call.calltitle)
        }
        guard let url = Bundle.main.url(forResource: "MarimbaRingtone", withExtension: "wav") else { return }
        playSound(soundUrl: url)
        player?.numberOfLoops = 2
    }

    /**
    * <iq from='hag66@shakespeare.lit/pda' id='h7ns81g' to='p2.glaciersec.cc' type='set'>
    *   <command xmlns='http://jabber.org/protocol/commands' action='execute' node='accept-call-apns'>
    *     <x xmlns="jabber:x:data" type="submit">
    *       <field var="callid"><value>237</value></field>
    *       <field var="receiverdevice"><value>152F11D4-9380-43E4-BCDE-B47314752B9B</value></field>
    *     </x>
    *   </command>
    * </iq>
    * Note: caller is a display name, but receiver is the bare JID of the receiver
    */
    @objc public func acceptCall(_ call: TwilioCall) {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        UIDevice.current.isProximityMonitoringEnabled = false;
        let callid = call.callid?.stringValue
        let me = self.cAccount?.displayName  
        self.currentCall = call
        
        // This is a public method, so it may be invoked on any thread/queue.
        self.performBlock(async: true){
            let command = XMLElement(name: "command", xmlns: CallManager.XMPPCommandNamespace)
            command.addAttribute(withName: "action", stringValue: "execute")
            command.addAttribute(withName: "node", stringValue: "accept-call-apns")
            let x = XMLElement(name: "x", xmlns: "jabber:x:data")
            x.addAttribute(withName: "type", stringValue: "submit")
            
            let callidfield = XMLElement(name: "field")
            callidfield.addAttribute(withName: "var", stringValue: "callid")
            let callidval = XMLElement(name: "value", stringValue: callid)
            callidfield.addChild(callidval)
            
            let devicefield = XMLElement(name: "field")
            devicefield.addAttribute(withName: "var", stringValue: "receiverdevice")
            let deviceval = XMLElement(name: "value", stringValue: deviceId)
            devicefield.addChild(deviceval)
            
            x.addChild(callidfield)
            x.addChild(devicefield)
            
            command.addChild(x)
            let tojid = XMPPJID(string: "p2." + GlacierInfo.defaultHost())
            let iq = XMPPIQ.init(iqType: XMPPIQ.IQType.set, to: tojid, elementID: self.xmppStream?.generateUUID, child: command)
            iq.addAttribute(withName: "from", stringValue: (self.xmppStream?.myJID?.full ?? me)!)
            
            self.tracker?.add(iq, target: self, selector: #selector(self.handleAcceptCallResponse(_:)), timeout: 15)
            
            self.xmppStream?.send(iq)
        }
    }
    
    @objc private func handleAcceptCallResponse(_ iq: XMPPIQ) {
        let x = iq.childElement?.element(forName: "x", xmlns: "jabber:x:data")
        guard let fields = x?.elements(forName: "field") else { return  }
        let call = TwilioCall()
        for field in fields {
            if let fvar = field.attributeStringValue(forName: "var"), let fval = field.element(forName: "value")?.stringValue {
                if fvar == "call_id" {
                    if let number = NumberFormatter().number(from: fval) {
                        call.callid = number
                    }
                } else if fvar == "token" {
                    call.token = fval
                } else if fvar == "caller" {
                    call.caller = fval
                } else if fvar == "receiver" {
                    call.receiver = fval
                } else if fvar == "roomname" {
                    call.roomname = fval
                } else if fvar == "title" { 
                    call.calltitle = fval
                }
            }
        }
        
        if let callerjid = call.caller, let callid = call.callid, let tojid = XMPPJID(string: callerjid){
            self.performBlock(async: true){
                let updateElement = XMLElement(name: "x", xmlns: "jabber:x:callupdate")
                updateElement.addAttribute(withName: "callstatus", stringValue: "accept")
                updateElement.addAttribute(withName: "callid", stringValue: callid.stringValue)
                
                let xmppMessage = XMPPMessage(messageType: nil, to: tojid, elementID: UUID().uuidString, child: updateElement)
                
                self.xmppStream?.send(xmppMessage)
            }
        }
        
        call.callUuid = self.currentUuid
        call.outgoing = false
        self.currentCall = call
        
        if let tcall = self.currentCall {
            DispatchQueue.main.async {
                tcall.systemMessage = "Received call"
                OTRAppDelegate.appDelegate.conversationViewController.connectPhone(tcall)
            }
        }
    }

    @objc public func rejectCall(_ call: TwilioCall, busy: Bool) {
        let callid = call.callid?.stringValue
        let caller = self.cAccount?.displayName
        
        DDLogInfo("*** rejectCall isBusy: \(isBusy)")
        
        // This is a public method, so it may be invoked on any thread/queue.
        self.performBlock(async: true){
            let command = XMLElement(name: "command", xmlns: CallManager.XMPPCommandNamespace)
            command.addAttribute(withName: "action", stringValue: "execute")
            if (busy) {
                command.addAttribute(withName: "node", stringValue: "busy-call-apns")
            } else {
                command.addAttribute(withName: "node", stringValue: "reject-call-apns")
            }
            let x = XMLElement(name: "x", xmlns: "jabber:x:data")
            x.addAttribute(withName: "type", stringValue: "submit")
            
            let callidfield = XMLElement(name: "field")
            callidfield.addAttribute(withName: "var", stringValue: "callid")
            let callidval = XMLElement(name: "value", stringValue: callid)
            callidfield.addChild(callidval)
            
            x.addChild(callidfield)
            
            command.addChild(x)
            let tojid = XMPPJID(string: "p2." + GlacierInfo.defaultHost())
            let iq = XMPPIQ.init(iqType: XMPPIQ.IQType.set, to: tojid, elementID: self.xmppStream?.generateUUID, child: command)
            if let from = self.xmppStream?.myJID?.full ?? caller {
                iq.addAttribute(withName: "from", stringValue: from)
            }
            
            self.tracker?.add(iq, target: self, selector: #selector(self.handleRejectCallResponse(_:)), timeout: 15)
            
            self.xmppStream?.send(iq)
            
            self.isBusy = false
        }
    }
    
    @objc private func handleRejectCallResponse(_ iq: XMPPIQ) {
        DDLogInfo("*** handleRejectCallResponse iq: \(String(describing: iq.toStr))")
        
        let x = iq.childElement?.element(forName: "x", xmlns: "jabber:x:data")
        guard let fields = x?.elements(forName: "field") else { return  }
        let call = TwilioCall()
        for field in fields {
            if let fvar = field.attributeStringValue(forName: "var"), let fval = field.element(forName: "value")?.stringValue {
                if fvar == "call_id" {
                    if let number = NumberFormatter().number(from: fval) {
                        call.callid = number
                    }
                } else if fvar == "caller" {
                    call.caller = fval
                } 
            }
        }
        
        var busyresponse = false
        if let command = iq.element(forName: "command", xmlns: CallManager.XMPPCommandNamespace), let node = command.attributeStringValue(forName: "node"), node.starts(with: "busy") {
            busyresponse = true
        }
        
        // send message to caller jid
        if let callerjid = call.caller, let callid = call.callid, let tojid = XMPPJID(string: callerjid){ //}, let acct = self.cAccount {
            
            self.performBlock(async: true){
                
                let updateElement = XMLElement(name: "x", xmlns: "jabber:x:callupdate")
                if (busyresponse) {
                    updateElement.addAttribute(withName: "callstatus", stringValue: "busy")
                    
                    DispatchQueue.main.async {
                        let sysmsg = "Missed call"
                        let user = (tojid.user ?? callerjid)!
                        OTRAppDelegate.appDelegate.conversationViewController.addSystemMessage(sysmsg, withCallerJID: callerjid, withUser: user)
                    }
                } else {
                    updateElement.addAttribute(withName: "callstatus", stringValue: "reject")
                }
                updateElement.addAttribute(withName: "callid", stringValue: callid.stringValue)
                
                let xmppMessage = XMPPMessage(messageType: nil, to: tojid, elementID: UUID().uuidString, child: updateElement)
                
                self.xmppStream?.send(xmppMessage)
            }
        }
    }
    
    @objc public func cancelCall(_ call: TwilioCall) {
        let callid = call.callid?.stringValue
        let caller = self.cAccount?.displayName
        
        // This is a public method, so it may be invoked on any thread/queue.
        self.performBlock(async: true){
            let command = XMLElement(name: "command", xmlns: CallManager.XMPPCommandNamespace)
            command.addAttribute(withName: "action", stringValue: "execute")
            command.addAttribute(withName: "node", stringValue: "cancel-call-apns")
            let x = XMLElement(name: "x", xmlns: "jabber:x:data")
            x.addAttribute(withName: "type", stringValue: "submit")
            
            let callidfield = XMLElement(name: "field")
            callidfield.addAttribute(withName: "var", stringValue: "callid")
            let callidval = XMLElement(name: "value", stringValue: callid)
            callidfield.addChild(callidval)
            
            x.addChild(callidfield)
            command.addChild(x)
            let tojid = XMPPJID(string: "p2." + GlacierInfo.defaultHost())
            let iq = XMPPIQ.init(iqType: XMPPIQ.IQType.set, to: tojid, elementID: self.xmppStream?.generateUUID, child: command)
            iq.addAttribute(withName: "from", stringValue: (self.xmppStream?.myJID?.full ?? caller)!)
            
            self.xmppStream?.send(iq)
        }
        
        if let receivers = call.receiver?.components(separatedBy: ","), let callid = call.callid {
            for receiver in receivers {
                if let tojid = XMPPJID(string: receiver) {
                    self.performBlock(async: true){
                        let updateElement = XMLElement(name: "x", xmlns: "jabber:x:callupdate")
                        updateElement.addAttribute(withName: "callstatus", stringValue: "cancel")
                        updateElement.addAttribute(withName: "callid", stringValue: callid.stringValue)
                    
                        let xmppMessage = XMPPMessage(messageType: nil, to: tojid, elementID: UUID().uuidString, child: updateElement)
                    
                        self.xmppStream?.send(xmppMessage)
                    }
                }
            }
        }
    }
}

extension CallManager: XMPPStreamDelegate {
    public func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ)  -> Bool {
        var result = false
        if let type = iq.type, type == XMPPIQ.IQType.result.rawValue || type == XMPPIQ.IQType.error.rawValue {
            self.performBlock(async: true){
                result = self.tracker?.invoke(for: iq, with: iq) ?? false
            }
        }
        return result;
    }
    
    public func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        guard !message.containsGroupChatElements,
            // We handle carbons elsewhere via XMPPMessageCarbonsDelegate
            !message.isMessageCarbon,
            // We handle MAM elsewhere as well
            message.mamResult == nil,
            // OMEMO messages cannot be processed here
            !message.omemo_hasEncryptedElement(.conversationsLegacy),
            !message.isMessageWithBody else {
            return
        }
        
        if message.containsCallElements {
            if let callupdate = message.element(forName: "x", xmlns: "jabber:x:callupdate"), let callstatus = callupdate.attributeStringValue(forName: "callstatus"), let callid = callupdate.attributeStringValue(forName: "callid"), let from = message.from?.bare {
                if (callstatus == "accept") {
                    reportCallAccepted(from, callid: callid)
                } else if (callstatus == "reject") {
                    reportCallRejected()
                } else if (callstatus == "cancel") {
                    reportCallCancelled()
                } else if (callstatus == "busy") {
                    reportCallBusy()
                }
            }
        }
    }
}

@objc public class TwilioCall:NSObject {
    @objc public var caller:String?
    @objc public var receiver:String?
    @objc public var roomname:String?
    @objc public var token:String?
    @objc public var callid:NSNumber?
    @objc public var calltitle:String? 
    @objc public var status:String?
    @objc public var systemMessage:String?
    @objc public var callUuid:UUID?
    @objc public var outgoing:Bool = true
}

extension CallManager : CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        DDLogInfo("Twilio providerDidReset:")

        // AudioDevice is enabled by default
        self.audioDevice.isEnabled = true
        
        tdelegate?.disconnectCall(false)
    }

    public func providerDidBegin(_ provider: CXProvider) {
        DDLogInfo("Twilio providerDidBegin")
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        DDLogInfo("Twilio provider:didActivateAudioSession:")

        self.audioDevice.isEnabled = true
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        DDLogInfo("Twilio provider:didDeactivateAudioSession:")
    }

    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        DDLogInfo("Twilio provider:timedOutPerformingAction:")
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        DDLogInfo("Twilio provider:performStartCallAction:")

        /*
         * Configure the audio session, but do not start call audio here, since it must be done once
         * the audio session has been activated by the system after having its priority elevated.
         */

        callKitProvider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        DDLogInfo("Twilio provider:performAnswerCallAction:")

        /*
         * Configure the audio session, but do not start call audio here, since it must be done once
         * the audio session has been activated by the system after having its priority elevated.
         */
        
        if self.currentCall != nil {
            self.handleAnswerCall()
            action.fulfill(withDateConnected: Date()) // don't like this
        } else {
            action.fail()
        }
        
        self.awaitingCallResponse = false
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        DDLogInfo("Twilio provider:performEndCallAction: with *** isBusy: \(isBusy)")
        
        self.callTimeout?.cancel()
        
        if (isBusy) {
            self.handleBusyCall()
            action.fulfill()
            return
        }
        
        if (!userInitiatedDisconnect) {
            tdelegate?.disconnectCall(false)
        }
        //room?.disconnect()
        
        if self.awaitingCallResponse {
            self.handleRejectCall()
        }

        self.awaitingCallResponse = false
        self.waitingToAnswerCall = false
        self.currentUuid = nil
        self.currentCall = nil
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        DDLogInfo("Twilio provider:performSetMutedCallAction:")
        
        tdelegate?.muteAudio(action.isMuted)
        
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        DDLogInfo("Twilio provider:performSetHeldCallAction:")

        let cxObserver = callKitCallController.callObserver
        let calls = cxObserver.calls

        guard let call = calls.first(where:{$0.uuid == action.callUUID}) else {
            action.fail()
            return
        }

        if call.isOnHold {
            tdelegate?.holdCall(false)
        } else {
            tdelegate?.holdCall(true)
        }
        
        action.fulfill()
    }
}

extension CallManager {

    func performStartCallAction(uuid: UUID, receiver: String?) {
        let callHandle = CXHandle(type: .generic, value: receiver ?? "")
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        
        startCallAction.isVideo = false
        
        let transaction = CXTransaction(action: startCallAction)
        
        callKitCallController.request(transaction)  { error in
            if let error = error {
                DDLogError("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }
            DDLogInfo("StartCallAction transaction request successful")
        }
    }
    
    func handleAnswerCall() {
        if let acct = self.cAccount, let tcall = self.currentCall {
            if OTRProtocolManager.sharedInstance().isAccountConnected(acct) {
                self.acceptCall(tcall)
            } else {
                self.waitingToAnswerCall = true
            }
        }
    }
    
    func handleBusyCall() {
        if let acct = self.cAccount, let bid = self.busyId {
            if OTRProtocolManager.sharedInstance().isAccountConnected(acct) {
                let bcall = TwilioCall()
                bcall.callid = bid
                self.rejectCall(bcall, busy: true)
            } else {
                self.waitingToRespondBusy = true
            }
        }
    }
    
    func handleRejectCall() {
        if let acct = self.cAccount, let tcall = self.currentCall {
            if OTRProtocolManager.sharedInstance().isAccountConnected(acct) {
                self.rejectCall(tcall, busy: false)
            } else {
                self.waitingToRespondReject = true
            }
        }
    }
    
    @objc func handleLoginSuccess() {
        if (self.waitingToAnswerCall) {
            if let tcall = self.currentCall {
                self.acceptCall(tcall)
            }
        } else if (self.waitingToRespondBusy) {
            handleBusyCall()
        } else if (self.waitingToRespondReject) {
            handleRejectCall()
        }
        self.waitingToAnswerCall = false
        self.waitingToRespondBusy = false
        self.waitingToRespondReject = false
    }
    
    func isBluetoothAvailable() -> Bool {
        return self.bluetoothAvailable
    }
    
    @objc func audioRouteChange(_ notification:Notification) {
        
        let session = AVAudioSession.sharedInstance()
        let newRoute = session.currentRoute
        if (newRoute.outputs.count > 0) {
            let route = newRoute.outputs[0].portType
            if ((route == AVAudioSessionPortBluetoothA2DP || route == AVAudioSessionPortBluetoothHFP)) {
                if (!bluetoothAvailable) {
                    bluetoothAvailable = true
                    tdelegate?.setBluetoothEnabled(bluetoothAvailable)
                }
            } else {
                if (bluetoothAvailable) {
                    bluetoothAvailable = false
                    tdelegate?.setBluetoothEnabled(bluetoothAvailable)
                }
            }
        }
    }
    
    @objc func isRinging() -> Bool {
        if (self.awaitingCallResponse) {
            return true
        }
        return false
    }

    @objc public func reportIncomingCall(uuid: UUID, callId: NSNumber, caller: String, completion: ((NSError?) -> Void)? = nil) {
        
        var inCall = false
        if (self.currentCall == nil) {
            self.currentUuid = uuid
            let call = TwilioCall()
            call.callid = callId
            call.caller = caller
            call.callUuid = uuid
            self.currentCall = call
            self.awaitingCallResponse = true
        } else {
            inCall = true
        }
        
        let callHandle = CXHandle(type: .generic, value: caller)

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = false
        callUpdate.supportsHolding = false
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false

        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if error == nil {
                DDLogInfo("Incoming call successfully reported.")
            } else {
                DDLogInfo("Failed to report incoming call successfully: \(String(describing: error?.localizedDescription)).")
            }
            
            if (inCall) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.handleBusy(uuid: uuid, busyId: callId)
                }
            }
            
            completion?(error as NSError?)
        }
        
        if (!inCall) {
            let task = DispatchWorkItem { self.performTimeout() }
            callTimeout = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: callTimeout!)
        }
    }
    
    private func performTimeout() {
        if (self.awaitingCallResponse || self.waitingToAnswerCall) {
            if let uuid = self.currentUuid {
                self.performEndCallAction(uuid: uuid, userInitiated: false)
            }
        }
    }
    
    @objc public func reportCallAccepted() {
        //might need to match up uuid or something with current call from notification
        if let tcall = self.currentCall {
            DispatchQueue.main.async {
                OTRAppDelegate.appDelegate.conversationViewController.connectPhone(tcall)
            }
        }
    }
    
    @objc public func reportCallAccepted(_ from:String, callid:String) {
        //might need to match up uuid or something with current call from notification
        if let tcall = self.currentCall, let acct = self.cAccount {
            
            // check if this particular call is already in progress. If so
            //this is likely a group call and I don't need to handle it here
            if let number = NumberFormatter().number(from: callid), tcall.status == "inprogress" || tcall.status == "accept", number == tcall.callid {
                return;
            }
            self.currentCall?.receiver = from
            self.currentCall?.status = "accept"
            
            DispatchQueue.main.async {
                OTRAppDelegate.appDelegate.conversationViewController.connectPhone(tcall)
            }
        }
    }
    
    @objc public func reportCallRejected() {
        // if in room, no reason to close call here.
        // handles the case of a second phone also waiting
        if let tdel = tdelegate {
            if (!tdel.isConnected()) {
                if let uuid = self.currentUuid {
                    guard let url = Bundle.main.url(forResource: "MarimbaFailed", withExtension: "wav") else { return }
                    playSound(soundUrl: url)
                    performEndCallAction(uuid: uuid, userInitiated: false)
                }
            }
        }
    }
    
    @objc public func reportCallBusy() {
        if (self.busyTone == true) {
            return // busy already in progress
        }
        
        guard let soundUrl = Bundle.main.url(forResource: "BusySignal", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: soundUrl, fileTypeHint: AVFileType.mp3.rawValue)
            player?.numberOfLoops = 2
        } catch _ {
            return // if it doesn't exist, don't play it
        }

        guard let player = player else { return }

        player.play()
        self.busyTone = true
        tdelegate?.setStatus("Busy")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if let _ = self.currentUuid, self.busyTone {
                self.performCancelCallAction(userInitiated: false) //not actually true but needed here
            }
        }
    }
    
    func playSound(soundUrl: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: soundUrl, fileTypeHint: AVFileType.wav.rawValue)
        } catch _ {
            return // if it doesn't exist, don't play it
        }

        guard let player = player else { return }

        player.play()
    }
    
    func stopSound() {
        self.busyTone = false
        guard let player = player else { return }
        player.stop()
    }
    
    @objc public func reportCallCancelled() {
        if let uuid = self.currentUuid {
            awaitingCallResponse = false
            performEndCallAction(uuid: uuid, userInitiated: false)
            
            if let tcall = self.currentCall {
                tcall.systemMessage = "Missed call"
                DispatchQueue.main.async {
                    if let caller = tcall.caller {
                        let sysmsg = "Missed call"
                        OTRAppDelegate.appDelegate.conversationViewController.addSystemMessage(sysmsg, withCallerJID: caller, withUser: caller)
                    }
                }
            }
        }
    }
    
    func performCancelCallAction(userInitiated: Bool) {
        if let uuid = self.currentUuid {
            if let tcall = self.currentCall {
                if (userInitiated && !self.busyTone) { 
                    self.cancelCall(tcall)
                }
            }
            performEndCallAction(uuid: uuid, userInitiated: userInitiated)
        }
    }

    func performEndCallAction(uuid: UUID, userInitiated: Bool) {
        // give it a second or two?
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.stopSound()
        }
        userInitiatedDisconnect = userInitiated
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { error in
            
            if let error = error {
                DDLogInfo("EndCallAction transaction request failed: \(error.localizedDescription).")
                return
            }

            DDLogInfo("EndCallAction transaction request successful")
        }
    }
    
    func handleBusy(uuid: UUID, busyId: NSNumber) {
        self.isBusy = true
        self.busyId = busyId
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { error in
            if let error = error {
                DDLogInfo("EndCallAction transaction request failed: \(error.localizedDescription).")
                return
            }

            DDLogInfo("EndCallAction transaction request successful")
        }
    }
    
    func reportCallDisconnected(uuid: UUID, error: Error?) {
        self.isBusy = false
        self.busyTone = false
        
        if !userInitiatedDisconnect, let error = error {
            var reason = CXCallEndedReason.remoteEnded

            if (error as NSError).code != TwilioVideoSDK.Error.roomRoomCompletedError.rawValue {
                reason = .failed
            }

            self.callKitProvider.reportCall(with: uuid, endedAt: nil, reason: reason)
        } else {
            self.awaitingCallResponse = false
            self.waitingToAnswerCall = false
            self.currentUuid = nil
            self.currentCall = nil
        }
        
        self.userInitiatedDisconnect = false
    }
    
    @objc public func reportCallConnected(uuid: UUID?, connectTime: Date) {
        self.stopSound()
        
        self.currentCall?.status = "inprogress"
        
        let cxObserver = callKitCallController.callObserver
        let calls = cxObserver.calls
        if let call = calls.first(where:{$0.uuid == uuid}) {
            if call.isOutgoing {
                if let calluuid = uuid {
                    self.callKitProvider.reportOutgoingCall(with: calluuid, connectedAt: connectTime)
                } else if let myuuid = self.currentUuid {
                    self.callKitProvider.reportOutgoingCall(with: myuuid, connectedAt: connectTime)
                }
            }
        }
        
        checkAudioPermissions()
    }
    
    @objc public func checkAudioPermissions() -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission() {
        case AVAudioSessionRecordPermission.denied:
            tdelegate?.handleAudioDenied()
            return true
        case AVAudioSessionRecordPermission.undetermined:
            tdelegate?.handleAudioDenied()
            return true
        case AVAudioSessionRecordPermission.granted: break
        default:
            break
        }
        
        return false
    }
    
    @objc public func performMuteAction(uuid: UUID, isMuted: Bool) {
        let muteAction = CXSetMutedCallAction(call: uuid, muted: isMuted)
        let transaction = CXTransaction(action: muteAction)

        callKitCallController.request(transaction)  { error in
            DispatchQueue.main.async {
                if let error = error {
                    DDLogError("SetMutedCallAction transaction request failed: \(error.localizedDescription)")
                    return
                }
                DDLogInfo("SetMutedCallAction transaction request successful")
            }
        }
    }
    
    @objc public func performSpeakerAction(isSelected: Bool) {
        self.audioDevice.block = {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                if(isSelected) {
                    try audioSession.setMode(AVAudioSessionModeVideoChat)
                    if (self.bluetoothAvailable) {
                        try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
                    }
                } else {
                    try audioSession.setMode(AVAudioSessionModeVoiceChat)
                    try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                }
            } catch {
                DDLogInfo("Fail: \(error.localizedDescription)")
            }
        }
        
        self.audioDevice.block()
    }
    
    public func performSpeakerAction(selection: SpeakerChoice) {
        self.audioDevice.block = {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                switch selection {
                    case SpeakerChoice.receiver:
                        try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, mode: AVAudioSessionModeVoiceChat, options: [])
                        try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                    case SpeakerChoice.speaker:
                        try audioSession.setMode(AVAudioSessionModeVideoChat)
                        if (self.bluetoothAvailable) {
                            try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
                        }
                    case SpeakerChoice.bluetooth:
                        try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, mode: AVAudioSessionModeVoiceChat, options: AVAudioSession.CategoryOptions.allowBluetooth)
                        try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                }
            } catch {
                DDLogInfo("Fail: \(error.localizedDescription)")
            }
        }
        
        self.audioDevice.block()
    }
    
    @objc public func performVideoAction() {
        tdelegate?.turnOnVideo()
    }
}

