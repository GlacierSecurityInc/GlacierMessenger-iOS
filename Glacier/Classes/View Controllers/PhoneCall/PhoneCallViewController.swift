//
//  PhoneCallViewController.swift
//  Created by Guillermo Olmedo on 4/15/20.
//  Copyright © 2020 Glacier Security. All rights reserved.
//

import UIKit
import Foundation
import Font_Awesome_Swift
import TwilioVideo
import CallKit

@objc open class PhoneCallViewController: UIViewController, TwilioCallDelegateProtocol {
    
    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var minimizedView: UIView!
    
    @IBOutlet weak var miniMuteLabel: UILabel!
    @IBOutlet weak var miniBarTitleLabel: UILabel!
    
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var remoteParticipantsView: CallVideoGrid!
    
    @IBOutlet weak var signalStateLabel: UILabel!
    
    @IBOutlet weak var topView: UIView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var muteButton: UIButton!
    @IBOutlet weak var videoButton: UIButton!
    @IBOutlet weak var speakerButton: UIButton!
    @IBOutlet weak var flipButton: UIButton!
    
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var mutedMark: UIButton!
    
    @IBOutlet weak var bottomView: UIView!
    
    var callManager: CallManager?
    
    var connectCompletionHandler: ((Bool)->Swift.Void?)? = nil
    
    var room: Room?
    var camera: CameraSource?
    var localVideoTrack: LocalVideoTrack?
    var localAudioTrack: LocalAudioTrack?
    @IBOutlet weak var localView: VideoView!
    
    var callTimer: Timer?
    var callTimeCount = 0
    var idleCount = 0
    var currentCall: TwilioCall?
    var nameTitle: String?
    var bluetoothPossible:Bool = false
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // We are done with camera
        if let camera = self.camera {
            camera.stopCapture()
            self.camera = nil
        }
    }
    
    @objc public func setCallManager(_ callManager: CallManager) {
        self.callManager = callManager
    }
    
    @objc public func setNameTitle(_ name: String) {
        self.nameTitle = name.capitalized
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        let mainTapGesture = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        mainView.isUserInteractionEnabled = true
        mainView.addGestureRecognizer(mainTapGesture)
        
        let miniTapGesture = UITapGestureRecognizer(target: self, action: #selector(minimizedViewTapped))
        minimizedView.isUserInteractionEnabled = true
        minimizedView.addGestureRecognizer(miniTapGesture)
        
        UIApplication.shared.isIdleTimerDisabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: Notification.Name.UIApplicationDidBecomeActive, object: nil)
        
        setupViews()
    }
    
    @objc private func becameActive() {
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        // Allow the device to sleep.
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        profileImageView.layer.cornerRadius = profileImageView.frame.height / 2.0
        profileImageView.clipsToBounds = true
        
        muteButton.layer.cornerRadius = muteButton.frame.height / 2
        muteButton.clipsToBounds = true
        videoButton.layer.cornerRadius = videoButton.frame.height / 2
        videoButton.clipsToBounds = true
        speakerButton.layer.cornerRadius = speakerButton.frame.height / 2
        speakerButton.clipsToBounds = true
        flipButton.layer.cornerRadius = flipButton.frame.height / 2
        flipButton.clipsToBounds = true
        disconnectButton.layer.cornerRadius = disconnectButton.frame.height / 2
        disconnectButton.clipsToBounds = true
        
        signalStateLabel.layer.cornerRadius = signalStateLabel.frame.height / 2
        signalStateLabel.clipsToBounds = true
        mutedMark.layer.cornerRadius = mutedMark.frame.height / 2
        mutedMark.clipsToBounds = true
    }
    
    // MARK: - UI
    
    private func setupViews() {
        localView.layer.cornerRadius = 10.0
        localView.clipsToBounds = true
        localView.contentMode = .scaleAspectFill;
        
        var localWidth = 63
        var localHeight = 112
        if (self.view.frame.size.width > 750) {
            localWidth = 100
            localHeight = 178
        }
        NSLayoutConstraint.activate([
            localView.heightAnchor.constraint(equalToConstant: CGFloat(localHeight)),
            localView.widthAnchor.constraint(equalToConstant: CGFloat(localWidth))
        ])
        
        minimizedView.backgroundColor = .clear
        minimizedView.isHidden = true
        
        miniMuteLabel.setFAIcon(icon: .FAMicrophoneSlash, iconSize: 14)
        miniMuteLabel.isHidden = true
        
        miniBarTitleLabel.text = "TAP TO RETURN TO CALL - Ringing..."
        
        mutedMark.isHidden = true
        signalStateLabel.isHidden = true
        
        closeButton.tintColor = .white
        closeButton.setFAIcon(icon: .FAAngleDown, iconSize: 35, forState: UIControl.State())
        
        signalStateLabel.backgroundColor = .orange
        signalStateLabel.textColor = .white
        signalStateLabel.alpha = 0.7
        
        var normalImage: UIImage?
        var selectedImage: UIImage?
        
        normalImage = UIImage(named: "ic-mute-off", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        selectedImage = UIImage(named: "ic-mute-on", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        muteButton.setImage(normalImage, for: .normal)
        muteButton.setImage(selectedImage, for: .selected)
        
        selectedImage = UIImage(named: "ic-video-on", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        normalImage = UIImage(named: "ic-video-off", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        videoButton.setImage(normalImage, for: .normal)
        videoButton.setImage(selectedImage, for: .selected)
        videoButton.isSelected = false
        videoButton.isEnabled = false
        
        normalImage = UIImage(named: "ic-speaker-off", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        selectedImage = UIImage(named: "ic-speaker-on", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        speakerButton.setImage(selectedImage, for: .selected)
        speakerButton.setImage(normalImage, for: .normal)
        speakerButton.isEnabled = false
        
        // if bluetooth
        if callManager?.isBluetoothAvailable() ?? false {
            normalImage = UIImage(named: "ic-bluetooth-on", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
            speakerButton.setImage(normalImage, for: .normal)
        }
        
        normalImage = UIImage(named: "ic-flip-camera", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
        flipButton.setImage(normalImage, for: UIControl.State())
        flipButton.isHidden = true
        
        if (nameTitle != nil) {
            nameLabel?.text = nameTitle
        }
        
        disconnectButton.backgroundColor = .red
        disconnectButton.tintColor = .white
        if #available(iOS 13.0, *) {
            let buttonConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            let phoneDown = UIImage(systemName: "phone.down.fill", withConfiguration: buttonConfiguration)
            disconnectButton.setImage(phoneDown, for: UIControl.State())
        } else {
            disconnectButton.setFAIcon(icon: .FAPhone, iconSize: 35, forState: UIControl.State())
        }
    }
    
    //TwilioCallDelegateProtocol
    public func connectCall(_ call: TwilioCall) {
        self.currentCall = call
        
        performRoomConnect(call: call) { (success) in
            if (success) {
                self.callManager?.reportCallConnected(uuid: call.callUuid, connectTime: Date())
                self.videoButton.isEnabled = true
                self.speakerButton.isEnabled = true
            } else {
                self.disconnectAction(self.disconnectButton)
                //maybe alert user
            }
        }
    }
    
    func performRoomConnect(call: TwilioCall, completionHandler: @escaping (Bool) -> Swift.Void) {
        
        self.connectCompletionHandler = completionHandler
        guard let token = call.token, let roomname = call.roomname else {
            self.connectCompletionHandler!(false)
            return
        }
        
        // Prepare local media which we will share with Room Participants.
        self.prepareLocalMedia()
        
        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: token) { (builder) in
            
            // Use the local media that we prepared earlier.
            builder.audioTracks = self.localAudioTrack != nil ? [self.localAudioTrack!] : [LocalAudioTrack]()
            builder.videoTracks = self.localVideoTrack != nil ? [self.localVideoTrack!] : [LocalVideoTrack]()
            
            builder.isAutomaticSubscriptionEnabled = true
            builder.roomName = roomname
                
            // The CallKit UUID to assoicate with this Room.
            builder.uuid = call.callUuid
        }
        
        // Connect to the Room using the options we provided.
        self.room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
        
        DDLogInfo("Twilio Attempting to connect to room \(String(describing: call.roomname))")
    }
    
    func prepareLocalMedia() {

        // We will share local audio and video when we connect to the Room.
        // Create an audio track.
        if (localAudioTrack == nil) {
            localAudioTrack = LocalAudioTrack()

            if (localAudioTrack == nil) {
                DDLogError("Twilio Failed to create audio track")
            }
        }

         // Create a video track which captures from the camera.
         if (localVideoTrack == nil) {
            localView.isHidden = true
            flipButton.isHidden = true
            videoButton.isSelected = false
            self.startPreview()
         }
    }
    
    public func handleAudioDenied() {
        handlePermissionDenied("Allow Audio", message: "Whoops! It looks like you have not permitted Glacier to access your Microphone. To use Glacier calling, please turn on Microphone while using the app in your device Glacier settings.")
    }
    
    func handleVideoDenied() {
        handlePermissionDenied("Allow Video", message: "Whoops! It looks like you have not permitted Glacier to access your Camera. To use Glacier video calling, please turn on Camera while using the app in your device Glacier settings.")
    }
    
    func handlePermissionDenied(_ title: String, message: String) {
        DispatchQueue.main.async {
            let permissionAlert = UIAlertController(title: title, message: message, preferredStyle: UIAlertControllerStyle.alert)

            permissionAlert.addAction(UIAlertAction(title: "Enable", style: UIAlertActionStyle.default, handler: { (action) -> Void in
                if let appSettings = URL(string: UIApplicationOpenSettingsURLString) {
                    Application.shared.open(appSettings, options: [:], completionHandler: nil)
                }
            }))
            permissionAlert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action) -> Void in
                //do nothing
            }))
            self.present(permissionAlert, animated: true, completion: nil)
        }
    }
    
    // MARK:- Private
    
    func startPreview() {
        let frontCamera = CameraSource.captureDevice(position: .front)
        let backCamera = CameraSource.captureDevice(position: .back)

        if (frontCamera != nil || backCamera != nil) {

            let options = CameraSourceOptions { (builder) in
                if #available(iOS 13.0, *) {
                    // Track UIWindowScene events for the key window's scene.
                    // The example app disables multi-window support in the .plist (see UIApplicationSceneManifestKey).
                    builder.orientationTracker = UserInterfaceTracker(scene: UIApplication.shared.keyWindow!.windowScene!)
                }
            }
            // Preview our local camera track in the local video preview view.
            camera = CameraSource(options: options, delegate: self)
            localVideoTrack = LocalVideoTrack(source: camera!, enabled: false, name: "Camera")

            // Add renderer to video track for local preview
            localVideoTrack!.addRenderer(self.localView)

            camera!.startCapture(device: frontCamera != nil ? frontCamera! : backCamera!) { (captureDevice, videoFormat, error) in
                if let error = error {
                    DDLogError("Twilio Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                } else {
                    self.localView.shouldMirror = (captureDevice.position == .front)
                }
            }
        }
        else {
            DDLogInfo("Twilio No front or back capture device found!")
        }
    }
    
    @objc public func doConnectCall(_ call: TwilioCall, with: String) {
        //self.buddy = with
        self.connectCall(call)
        
        nameLabel.text = with.capitalized//with.displayName.capitalized
    }
    
    private func showCallMenu(state: Bool) {
        UIView.animate(withDuration: 0.4, animations: {
            self.topView.alpha = state ? 1.0 : 0
            self.buttonView.alpha = state ? 1.0 : 0
        }, completion: { _ in
            self.topView.isHidden = !state
            self.buttonView.isHidden = !state
        })
    }
    
    private func killCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
    
    // MARK: - Callbacks
    
    @objc func viewTapped() {
        idleCount = 0
        showCallMenu(state: true)
    }
    
    @objc func minimizedViewTapped() {
        let appDelegate = UIApplication.shared.delegate as! OTRAppDelegate
        let screenSize = UIScreen.main.bounds
        appDelegate.callWindow.backgroundColor = .clear
        appDelegate.callWindow.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        minimizedView.isHidden = true
        mainView.isHidden = false
        bottomView.isHidden = false
        
        appDelegate.messagesViewController.view.endEditing(true)
        
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
            self.mainView.alpha = 1.0
        }, completion: nil)
        
        appDelegate.window?.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
    }
    
    @objc func processCallTimer() {
        callTimeCount += 1
        if idleCount >= 0 { idleCount += 1 }
        
        if idleCount > 10 {
            idleCount = -1
            showCallMenu(state: false)
        }
        
        if callTimeCount < 3600 {
            let minutes = callTimeCount / 60
            let seconds = callTimeCount % 60
            progressLabel.text = String(format: "%02d:%02d", minutes, seconds)
        } else {
            let hours = callTimeCount / (60 * 60)
            let minutes = callTimeCount / 60
            let seconds = callTimeCount % 60
            progressLabel.text = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        
        miniBarTitleLabel.text = "TAP TO RETURN TO CALL - \(progressLabel.text ?? "")"
    }
    
    @IBAction func muteAction(_ sender: UIButton) {
        if let room = room, let uuid = room.uuid, let localAudioTrack = self.localAudioTrack {
            let isMuted = localAudioTrack.isEnabled
        
            self.callManager?.performMuteAction(uuid: uuid, isMuted: isMuted)
        }
        self.viewTapped()
    }
    
    public func muteAudio(_ isMuted: Bool) {
        muteButton.isSelected = isMuted
        if let localAudioTrack = self.localAudioTrack {
            localAudioTrack.isEnabled = !isMuted
            
            mutedMark.isHidden = !isMuted
            miniMuteLabel.isHidden = !isMuted
        }
    }
    
    @IBAction func videoAction(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        localView.isHidden = !sender.isSelected
        
        if (self.localVideoTrack != nil) {
            self.localVideoTrack?.isEnabled = !(self.localVideoTrack?.isEnabled)!
        }
        
        flipButton.isHidden = localView.isHidden
        
        //if goto video with bluetooth on, keep bluetooth on
        //if goto video with bluetooth off, turn on speaker
        //if off video with bluetooth on, keep bluetooth on
        //if off video with bluetooth off, turn off speaker
        if !speakerButton.isSelected && callManager?.isBluetoothAvailable() ?? false {
            self.callManager?.performSpeakerAction(selection: SpeakerChoice.bluetooth)
            speakerButton.isSelected = false
        } else {
            self.callManager?.performSpeakerAction(isSelected: sender.isSelected)
            speakerButton.isSelected = sender.isSelected
        }
        self.viewTapped()
    }
    
    public func setBluetoothEnabled(_ bluetoothEnabled: Bool) {
        DispatchQueue.main.async {
            var normalImage: UIImage?
            if (bluetoothEnabled) {
                normalImage = UIImage(named: "ic-bluetooth-on", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
                self.speakerButton.setImage(normalImage, for: .normal)
            } else {
                normalImage = UIImage(named: "ic-speaker-off", in: GlacierInfo.resourcesBundle, compatibleWith: nil)
                self.speakerButton.setImage(normalImage, for: .normal)
            }
        }
    }
    
    @IBAction func speakerAction(_ sender: UIButton) {
        
        if self.bluetoothPossible || callManager?.isBluetoothAvailable() ?? false {
            let actionsheet = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)

            actionsheet.addAction(UIAlertAction(title: "Bluetooth", style: UIAlertActionStyle.default, handler: { (action) -> Void in
                sender.isSelected = false
                self.callManager?.performSpeakerAction(selection: SpeakerChoice.bluetooth)
            }))
            actionsheet.addAction(UIAlertAction(title: "Speaker", style: UIAlertActionStyle.default, handler: { (action) -> Void in
                sender.isSelected = true
                self.callManager?.performSpeakerAction(selection: SpeakerChoice.speaker)
            }))
            actionsheet.addAction(UIAlertAction(title: "Phone", style: UIAlertActionStyle.default, handler: { (action) -> Void in
                sender.isSelected = false
                self.callManager?.performSpeakerAction(selection: SpeakerChoice.receiver)
                self.bluetoothPossible = true
            }))
            actionsheet.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action) -> Void in
                //do nothing
            }))
            self.present(actionsheet, animated: true, completion: nil)
        } else {
            sender.isSelected = !sender.isSelected
            self.callManager?.performSpeakerAction(isSelected: sender.isSelected)
        }
        self.viewTapped()
    }
    
    @IBAction func flipCameraAction(_ sender: UIButton) {
        
        var newDevice: AVCaptureDevice?

        if let camera = self.camera, let captureDevice = camera.device {
            if captureDevice.position == .front {
                newDevice = CameraSource.captureDevice(position: .back)
            } else {
                newDevice = CameraSource.captureDevice(position: .front)
            }

            if let newDevice = newDevice {
                camera.selectCaptureDevice(newDevice) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        DDLogInfo("Error selecting capture device.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
                        self.localView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
        self.viewTapped()
    }
    
    @IBAction func closeAction(_ sender: Any) {
        self.bottomView.isHidden = true
        let topSafeArea = view.safeAreaInsets.top
        let screenSize = UIScreen.main.bounds
        let appDelegate = UIApplication.shared.delegate as! OTRAppDelegate
        appDelegate.callWindow.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: topSafeArea + 44)
        appDelegate.callWindow.backgroundColor = .green
        
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
            self.mainView.alpha = 0
        }, completion: { _ in
            self.minimizedView.isHidden = false
            self.mainView.isHidden = true
        })
        
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        let phoneHeight:CGFloat = 20.0
        let safeHeight = (isiPhone ? phoneHeight : topSafeArea)
        
        appDelegate.window?.frame = CGRect(x: 0,
                                           y: safeHeight + 44.0,
                                           width: screenSize.width,
                                           height: screenSize.height - safeHeight - 44)
    }
    
    @IBAction func disconnectAction(_ sender: Any) {
        let ruuid = self.room?.uuid
        disconnectCall(true)
        
        // room doesn't exist yet if we haven't connected. What's the uuid then?
        if let uuid = ruuid {
            self.callManager?.performEndCallAction(uuid: uuid, userInitiated: true)
        } else {
            self.callManager?.performCancelCallAction(userInitiated: true)
        }
    }

    func cleanupRemoteParticipants() {
        remoteParticipantsView.removeAllParticipants()
    }
    
    public func holdCall(_ onHold: Bool) {
        localAudioTrack?.isEnabled = !onHold
        localVideoTrack?.isEnabled = !onHold
    }
    
    public func disconnectCall(_ userInitiated: Bool) {
        DDLogInfo("Twilio Attempting to disconnect from room \(String(describing: room?.name))")
        self.callManager?.performSpeakerAction(selection: SpeakerChoice.bluetooth)
        
        if (userInitiated) {
            if let url = Bundle.main.url(forResource: "MarimbaBlink", withExtension: "wav") {
                self.callManager?.playSound(soundUrl: url)
            }
        }
        
        self.room?.disconnect()
        killCallTimer()
        dismiss(animated: true) {
            let appDelegate = UIApplication.shared.delegate as! OTRAppDelegate
            appDelegate.callWindow.rootViewController = nil
            appDelegate.callWindow.frame = CGRect.zero
            appDelegate.callWindow.resignKey()
            appDelegate.messagesViewController.enablePhoneButton(true)
            UIApplication.shared.isIdleTimerDisabled = false 
        }
    }
    
    public func turnOnVideo() {
        self.videoAction(videoButton)
    }
    
    public func isConnected() -> Bool {
        if let conroom = self.room {
            return conroom.state == Room.State.connected
        }
        
        return false
    }
    
    public func setStatus(_ status: String) {
        DispatchQueue.main.async {
            self.progressLabel.text = status
        }
    }
}

// MARK:- VideoViewDelegate
extension PhoneCallViewController : VideoViewDelegate {
    open func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        self.view.setNeedsLayout()
    }
}

// MARK:- CameraSourceDelegate
extension PhoneCallViewController : CameraSourceDelegate {
    open func cameraSourceDidFail(source: CameraSource, error: Error) {
        DDLogError("Twilio Camera source failed with error: \(error.localizedDescription)")
    }
}

// MARK:- RoomDelegate
extension PhoneCallViewController : RoomDelegate {
    open func roomDidConnect(room: Room) {
        DDLogInfo("Twilio Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")")
        
        //self.speakerLabel.text = "SPEAKER"
        self.progressLabel.text = "00:00"
        self.miniBarTitleLabel.text = "TAP TO RETURN TO CALL - 00:00"
        
        self.callTimer = Timer.scheduledTimer(timeInterval: 1.0,
                                              target: self,
                                              selector: #selector(PhoneCallViewController.processCallTimer),
                                              userInfo: nil,
                                              repeats: true)

        self.profileImageView.isHidden = true
        for participant in room.remoteParticipants {
            var callbuddy = self.callManager?.getCallBuddy(participant.identity)
            
            if callbuddy == nil, let caller = self.currentCall?.caller, let callerbuddy = self.callManager?.getCallBuddy(caller), callerbuddy.displayName == participant.identity {
                callbuddy = callerbuddy
            }
            
            var displayname = callbuddy?.displayName
            var avatar = callbuddy?.avatarImage
            
            if (avatar == nil && displayname == nil) {
                displayname = participant.identity
                avatar = OTRImages.avatarImage(withUsername: displayname)
            }
            
            remoteParticipantsView.addParticipant(participant: participant, name: displayname, image: avatar)
        }
        
        self.connectCompletionHandler!(true)
    }

    open func roomDidDisconnect(room: Room, error: Error?) {
        DDLogInfo("Twilio Disconnected from room \(room.name), error = \(String(describing: error))")
        if let uuid = room.uuid {
            self.callManager?.reportCallDisconnected(uuid: uuid, error: error)
        }
        
        self.cleanupRemoteParticipants()
        self.room = nil
        
        self.connectCompletionHandler = nil
    }

    open func roomDidFailToConnect(room: Room, error: Error) {
        DDLogInfo("Twilio Failed to connect to room with error = \(String(describing: error))")
        self.connectCompletionHandler!(false)
        self.room = nil
    }

    open func roomIsReconnecting(room: Room, error: Error) {
        DDLogInfo("Twilio Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    open func roomDidReconnect(room: Room) {
        DDLogInfo("Twilio Reconnected to room \(room.name)")
    }

    open func participantDidConnect(room: Room, participant: RemoteParticipant) {
        // Listen for events from all Participants to decide which RemoteVideoTrack to render.
        var callbuddy = self.callManager?.getCallBuddy(participant.identity)
        
        if callbuddy == nil, let caller = self.currentCall?.caller, let callerbuddy = self.callManager?.getCallBuddy(caller), callerbuddy.displayName == participant.identity {
            callbuddy = callerbuddy
        }
        
        var displayname = callbuddy?.displayName
        var avatar = callbuddy?.avatarImage
        
        if (avatar == nil && displayname == nil) {
            displayname = participant.identity
            avatar = OTRImages.avatarImage(withUsername: displayname)
        }
        
        remoteParticipantsView.addParticipant(participant: participant, name: displayname, image: avatar)

        DDLogInfo("Twilio Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
        guard let url = Bundle.main.url(forResource: "MarimbaDing", withExtension: "wav") else { return }
        self.callManager?.playSound(soundUrl: url)
    }

    open func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        DDLogInfo("Twilio Room \(room.name), Participant \(participant.identity) disconnected")
        remoteParticipantsView.removeParticipant(participant: participant)
        if room.remoteParticipants.count == 0 {
            self.disconnectAction(self.disconnectButton)
        }
    }
}
