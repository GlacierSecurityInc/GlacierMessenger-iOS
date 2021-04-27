//
//  CallVideoGrid.swift
//  Glacier
//
//  Created by Andy Friedman on 1/26/21.
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import TwilioVideo
import PureLayout

class CallVideoGrid: UICollectionView {
    //weak var memberViewDelegate: CallMemberViewDelegate?
    let layout: CallVideoGridLayout
    var participantsArray: [CallParticipant] = []
    
    init() {
        self.layout = CallVideoGridLayout()
        super.init(frame: .zero, collectionViewLayout: layout)
        layout.delegate = self
        self.backgroundColor = GlobalTheme.shared.lightThemeColor

        register(CallVideoGridCell.self, forCellWithReuseIdentifier: CallVideoGridCell.reuseIdentifier)
        
        dataSource = self
        delegate = self
    }

    required init?(coder: NSCoder) {
        self.layout = CallVideoGridLayout()
    
        super.init(coder: coder)
        self.frame = .zero
        self.collectionViewLayout = layout
        layout.delegate = self
        self.backgroundColor = GlobalTheme.shared.lightThemeColor

        register(CallVideoGridCell.self, forCellWithReuseIdentifier: CallVideoGridCell.reuseIdentifier)
        dataSource = self
        delegate = self
    }

    //deinit { call.removeObserver(self) }
    
    func addParticipant(participant: RemoteParticipant, name: String?, image: UIImage?) {
        //this should go into an array/list that gets pulled in the data source
        //class CallParticipant should have Remote, name, image
        //then refresh data
        
        //create a VideoView here and add it
        let videoView = VideoView(frame: .zero)
        let callParticipant = CallParticipant(remoteParticipant: participant, view: videoView, image:image, name:name)
        callParticipant.participant.delegate = callParticipant
        callParticipant.participantView.delegate = self
        participantsArray.append(callParticipant)
        self.backgroundColor = GlobalTheme.shared.lightThemeColor
        
        DispatchQueue.main.async {
            self.reloadData()
        }
    }
    
    func removeParticipant(participant: RemoteParticipant) {
        participantsArray.removeAll(where: {$0.participant.identity == participant.identity})
        self.backgroundColor = GlobalTheme.shared.lightThemeColor
        DispatchQueue.main.async {
            self.reloadData()
        }
    }
    
    func removeAllParticipants() {
        participantsArray.removeAll()
        DispatchQueue.main.async {
            self.reloadData()
        }
    }
}

// MARK:- VideoViewDelegate
extension CallVideoGrid : VideoViewDelegate {
    open func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        self.setNeedsLayout()
    }
}

extension CallVideoGrid: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CallVideoGridCell else { return }
        cell.cleanupRemoteParticipant() 
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
    }
}

extension CallVideoGrid: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return participantsArray.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CallVideoGridCell.reuseIdentifier,
            for: indexPath
        ) as! CallVideoGridCell
        
        let participant = participantsArray[indexPath.row]
        DDLogInfo("collectionView cellForItemAt row: \(indexPath.row) with ID  \(participantsArray[indexPath.row].participant.identity)")
        
        cell.configure(participant: participant, numRecs: participantsArray.count)
        participant.setCallVideoCellDelegate(delegate: cell)
        
        return cell
    }
}

extension CallVideoGrid: CallVideoGridLayoutDelegate {
    var maxColumns: Int {
        //return 2
        let wide = width
        if wide > 1080 {
            return 4
        } else if wide > 768 {
            return 3
        } else {
            return 2
        }
    }

    var maxRows: Int {
        if height > 1024 {
            return 4
        } else {
            return 3
        }
    }
    
    var width: CGFloat {
        return self.frame.width
    }
    
    var height: CGFloat {
        return self.frame.height
    }

    var maxItems: Int { maxColumns * maxRows }
}

public protocol CallVideoCellDelegate: NSObjectProtocol {
    func doCleanup()
    func hideAvatar(hide:Bool)
    func showMuted(show:Bool)
}

class CallVideoGridCell: UICollectionViewCell {
    static let reuseIdentifier = "CallVideoGridCell"
    var callParticipant: CallParticipant?
    private var hasBeenConfigured = false
    private var oneOf = 1 //not good coding here
    
    let mutedView = UIButton()
    
    let avatarView = AvatarImageView()
    lazy var avatarWidthConstraint = avatarView.autoSetDimension(.width, toSize: CGFloat(avatarDiameter))
    var avatarDiameter: UInt {
        layoutIfNeeded()

        if bounds.width > 350 && oneOf <= 2 {
            return 240
        } else if bounds.width > 180 {
            return 112
        } else if bounds.width > 102 {
            return 96
        } else if bounds.width > 36 {
            return UInt(bounds.width) - 36
        } else {
            return 16
        }
    }
    
    override var bounds: CGRect {
        didSet { updateDimensions() }
    }

    override var frame: CGRect {
        didSet { updateDimensions() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
    }
    
    /*func setDelegate(videoViewDelegate: VideoViewDelegate) {
        callParticipant?.participantView.delegate = videoViewDelegate
    }*/
    
    func configure(participant: CallParticipant, numRecs: Int) {
        hasBeenConfigured = true
        oneOf = numRecs
        
        participant.participantView.frame = bounds
        contentView.addSubview(participant.participantView)
        participant.participantView.autoPinEdgesToSuperviewEdges()
        participant.participantView.contentMode = .scaleAspectFill
        
        if let img = participant.participantImage {
            avatarView.image = img
        } else {
            DDLogError("Can't find participantImage in configure")
        }
        
        contentView.addSubview(avatarView)
        avatarWidthConstraint.constant = CGFloat(avatarDiameter)
        avatarView.configureView(numRecs: oneOf)
        
        setupMicOffButton()
        mutedView.isHidden = !participant.isMuted
        
        // check if videoEnabled
        var hide = false
        let videoPublications = participant.participant.remoteVideoTracks
        for publication in videoPublications {
            if publication.isTrackEnabled {
                hide = true
            }
        }
        hideAvatar(hide: hide)
        
        callParticipant = participant
    }
    
    private func setupMicOffButton() {
        mutedView.translatesAutoresizingMaskIntoConstraints = false;
        if #available(iOS 13.0, *) {
            let micOffImage = UIImage(systemName: "mic.slash.fill")
            mutedView.setImage(micOffImage, for: UIControlState())
            mutedView.tintColor = UIColor.lightGray
        } else {
            mutedView.setTitle("MUTED", for: UIControlState())
            mutedView.setTitleColor(UIColor.lightGray, for: UIControlState())
        }
        mutedView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        mutedView.isHidden = true
        
        contentView.addSubview(mutedView)
        
        mutedView.autoPinEdge(.top, to: .bottom, of: avatarView, withOffset: 5.0)
        let xconstraint = NSLayoutConstraint(
            item: mutedView,
            attribute: .centerX,
            relatedBy: .equal,
            toItem: contentView,
            attribute: .centerX,
            multiplier: 1.0,
            constant: 0.0)
        contentView.addConstraint(xconstraint)
        xconstraint.isActive = true
    }
    
    private func updateDimensions() {
        guard hasBeenConfigured else { return }
        callParticipant?.participantView.frame = bounds
        avatarWidthConstraint.constant = CGFloat(avatarDiameter)
    }
    
    func cleanupRemoteParticipant() {
        callParticipant?.setCallVideoCellDelegate(delegate: nil)
        callParticipant?.participantView.removeFromSuperview()
        avatarView.removeFromSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CallVideoGridCell: CallVideoCellDelegate {
    func doCleanup() {
        cleanupRemoteParticipant()
    }
    
    func hideAvatar(hide:Bool) {
        avatarView.isHidden = hide
    }
    
    func showMuted(show:Bool) {
        mutedView.isHidden = !show
    }
}

class CallParticipant : NSObject {
    let participant: RemoteParticipant!
    let participantView: VideoView!
    var participantImage: UIImage?
    var participantName: String?
    var isMuted = false
    weak var callCellDelegate: CallVideoCellDelegate?
    
    public init(remoteParticipant: RemoteParticipant, view: VideoView, image: UIImage?, name: String?) {
        participant = remoteParticipant
        participantView = view
        participantImage = image
        participantName = name
    }
    
    func setCallVideoCellDelegate(delegate: CallVideoCellDelegate?) {
        callCellDelegate = delegate
    }
    
    func renderRemoteParticipant(participant : RemoteParticipant) -> Bool {
        let videoPublications = participant.remoteVideoTracks
        for publication in videoPublications {
            if let subscribedVideoTrack = publication.remoteTrack,
                publication.isTrackSubscribed {
                subscribedVideoTrack.addRenderer(participantView)
                //self.remoteParticipant = participant
                return true
            }
        }
        return false
    }
}

extension CallParticipant : RemoteParticipantDelegate {

    open func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has offered to share the video Track.
        
        DDLogError("Twilio Participant \(participant.identity) published \(publication.trackName) video track")
    }

    open func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has stopped sharing the video Track.
        DDLogError("Twilio Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    open func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has offered to share the audio Track.
        DDLogError("Twilio Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    open func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has stopped sharing the audio Track.
        DDLogError("Twilio Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    open func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // The LocalParticipant is subscribed to the RemoteParticipant's video Track. Frames will begin to arrive now.
        DDLogError("Twilio Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")
        
        if self.participant == participant {
            _ = renderRemoteParticipant(participant: participant)
        }else {
            DDLogError("Can't find participant in didSubscribeToVideoTrack")
        }
        
        if (videoTrack.isEnabled) {  //if let track = publication.remoteTrack
            callCellDelegate?.hideAvatar(hide: true)
        }
    }
    
    open func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.
        
        DDLogError("Twilio Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")
        
        callCellDelegate?.hideAvatar(hide: false)

        if self.participant == participant {
            let videoPublications = participant.remoteVideoTracks
            for publication in videoPublications {
                if let videoTrack = publication.remoteTrack {
                    videoTrack.removeRenderer(participantView)
                    return
                }
            }
        }
    }

    open func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.
       
        DDLogError("Twilio Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
    }
    
    open func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.
        
        DDLogError("Twilio Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    open func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        DDLogError("Twilio Participant \(participant.identity) enabled \(publication.trackName) video track")
        callCellDelegate?.hideAvatar(hide: true)
    }

    open func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        DDLogError("Twilio Participant \(participant.identity) disabled \(publication.trackName) video track")
        callCellDelegate?.hideAvatar(hide: false)
    }

    open func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        DDLogError("Twilio Participant \(participant.identity) enabled \(publication.trackName) audio track")
        callCellDelegate?.showMuted(show: false)
        self.isMuted = false
    }

    open func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        DDLogError("Twilio Participant \(participant.identity) disabled \(publication.trackName) audio track")
        callCellDelegate?.showMuted(show: true)
        self.isMuted = true
    }

    open func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        DDLogError("Twilio FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    open func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        DDLogError("Twilio FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

class AvatarImageView: UIImageView {

    public init() {
        super.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override init(image: UIImage?) {
        super.init(image: image)
    }

    func configureView(numRecs: Int) {
        self.autoPinConstraints(numRecs: numRecs)
        self.layer.masksToBounds = true
        self.contentMode = .scaleToFill
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.width / 2
    }
    
    func autoPinConstraints(numRecs: Int)
    {
        self.translatesAutoresizingMaskIntoConstraints = false;
        let constraint = NSLayoutConstraint(
            item: self,
            attribute: .width,
            relatedBy: .equal,
            toItem: self,
            attribute: .height,
            multiplier: 1.0,
            constant: 0.0)
        constraint.autoInstall()
        
        if (numRecs > 1) {
            autoCenterInSuperview()
        } else {
            let xconstraint = NSLayoutConstraint(
                item: self,
                attribute: .centerX,
                relatedBy: .equal,
                toItem: superview,
                attribute: .centerX,
                multiplier: 1.0,
                constant: 0.0)
            xconstraint.autoInstall()
        
            let yconstraint = NSLayoutConstraint(
                item: self,
                attribute: .centerY,
                relatedBy: .equal,
                toItem: superview,
                attribute: .centerY,
                multiplier: 0.8,
                constant: 0.0)
            yconstraint.autoInstall()
        }
    }
}
