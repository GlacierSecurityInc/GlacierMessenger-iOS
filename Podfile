# Disable CocoaPods deterministic UUIDs as Pods are not checked in
ENV["COCOAPODS_DISABLE_DETERMINISTIC_UUIDS"] = "true"

# Disable Bitcode for all targets http://stackoverflow.com/a/32685434/805882
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
      config.build_settings['CLANG_WARN_STRICT_PROTOTYPES'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      
      if target.name == "GlacierNotifications"
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'TARGET_IS_EXTENSION=1']
      end
      
      if target.name == "GlacierShare"
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'TARGET_IS_EXTENSION=1']
      end
    end
  end
end

platform :ios, "12.0"

use_frameworks!
# inhibit_all_warnings!

source 'https://github.com/CocoaPods/Specs.git'

abstract_target 'GlacierPods' do

  # https://github.com/zxingify/zxingify-objc/pull/491
  pod 'ZXingObjC/QRCode', :git => 'https://github.com/ChatSecure/ZXingObjC.git', :branch => 'fix-catalyst'
  
  # Network
  pod 'CocoaAsyncSocket', '~> 7.6.3'
  pod 'ProxyKit/Client', '~> 1.2.0'
  pod 'GCDWebServer', '~> 3.4.2'
  pod 'XMPPFramework/Swift', :path => 'Submodules/XMPPFramework/XMPPFramework.podspec'
  pod 'ChatSecure-Push-iOS', :path => 'Submodules/ChatSecure-Push-iOS/ChatSecure-Push-iOS.podspec'

  # Storage
  # Catalyst patch won't be merged upstream
  pod 'SQLCipher', :git => 'https://github.com/ChatSecure/sqlcipher.git', :branch => 'v4.3.0-catalyst'

  # Waiting on merge https://github.com/yapstudios/YapDatabase/pull/492
  pod 'YapDatabase/SQLCipher', :path => 'Submodules/YapDatabase/YapDatabase.podspec'

  # The upstream 1.3.2 has a regression https://github.com/ChatSecure/ChatSecure-iOS/issues/1075
  pod 'libsqlfs/SQLCipher', :path => 'Submodules/libsqlfs/libsqlfs.podspec'

  pod 'IOCipher/GCDWebServer', :path => 'Submodules/IOCipher/IOCipher.podspec'
  pod 'YapTaskQueue/SQLCipher', :path => 'Submodules/YapTaskQueue/YapTaskQueue.podspec'

  # Crypto
  pod 'SignalProtocolObjC', :path => 'Submodules/SignalProtocol-ObjC/SignalProtocolObjC.podspec'
  pod 'OTRKit', :path => 'Submodules/OTRKit/OTRKit.podspec'

  # User Interface
  pod 'JTSImageViewController', :git => 'https://github.com/afriedmanGlacier/JTSImageViewController.git'
  pod 'BButton', :git => 'https://github.com/jessesquires/BButton.git', :commit => 'b3d96ad996d9b71a82329c0ca724cad62564f977'
  pod 'ARChromeActivity', '~> 1.0.6'
  pod 'QRCodeReaderViewController', '~> 4.0.2'
  pod 'ParkedTextField', :git => 'https://github.com/gmertk/ParkedTextField.git', :commit => '43f1d3b' # Swift 4


  pod 'JSQMessagesViewController', :path => 'Submodules/JSQMessagesViewController/JSQMessagesViewController.podspec'
  pod 'AFNetworking', '~> 3.0', :source => 'https://github.com/ElfSundae/CocoaPods-Specs.git'
  pod 'Font-Awesome-Swift', '~> 1.7.2'
  pod 'TwilioVideo', '~> 4.0'

  # Debugging
  # pod 'Reveal-SDK', :configurations => ['Debug']
  # pod 'LumberjackConsole', '~> 3.3.0'
  pod 'LumberjackConsole', :path => 'Submodules/LumberjackConsole/LumberjackConsole.podspec'

  pod 'SAMKeychain', :git => 'https://github.com/afriedmanGlacier/SAMKeychain.git'
  pod 'DGActivityIndicatorView', :git => 'https://github.com/ninjaprox/DGActivityIndicatorView.git'
  pod 'MapboxStatic.swift', :git => 'https://github.com/afriedmanGlacier/MapboxStatic.swift'
  pod 'Mapbox-iOS-SDK', '~> 6.2.1'
  
  pod 'AWSCognito'
  pod 'AWSCognitoIdentityProvider'
  pod 'AWSS3'
  pod 'AWSCognitoAuth'
  pod 'AWSUserPoolsSignIn', '~> 2.17.0'
  pod 'AWSAppSync', ' ~> 3.1.9'

  pod 'DZNEmptyDataSet'
  pod 'SkeletonView', :git => 'https://github.com/afriedmanGlacier/SkeletonView.git'

  # Utility
  pod 'CocoaLumberjack/Swift', '~> 3.4.2'
  pod 'MWFeedParser', '~> 1.0'
  pod 'Navajo', '~> 0.0.1'
  pod 'BBlock', '~> 1.2.1'

  pod 'Alamofire', '~> 5.0'

  pod 'Mantle'
  pod 'HTMLReader', '~> 2.1.1'
  pod 'MBProgressHUD', '~> 1.1'
  pod 'TTTAttributedLabel', '~> 2.0'
  pod 'PureLayout', '~> 3.0'
  pod 'KVOController', '~> 1.2'
  pod 'XLForm', '~> 4.1'
  pod 'FormatterKit/TimeIntervalFormatter', '~> 1.8'
  pod 'FormatterKit/UnitOfInformationFormatter', '~> 1.8'

  target 'Glacier'
end

target 'GlacierNotifications' do

  pod 'SQLCipher', :git => 'https://github.com/ChatSecure/sqlcipher.git', :branch => 'v4.3.0-catalyst'
  pod 'YapDatabase/SQLCipher', :path => 'Submodules/YapDatabase/YapDatabase.podspec'
  
  pod 'SAMKeychain', :git => 'https://github.com/afriedmanGlacier/SAMKeychain.git'
  pod 'XMPPFramework/Swift', :path => 'Submodules/XMPPFramework/XMPPFramework.podspec'
  pod 'BBlock', '~> 1.2.1'
  pod 'KVOController', '~> 1.2'
  pod 'CocoaLumberjack/Swift', '~> 3.4.2'

  # pod 'IOCipher/GCDWebServer', :path => 'Submodules/IOCipher/IOCipher.podspec'
  pod 'YapTaskQueue/SQLCipher', :path => 'Submodules/YapTaskQueue/YapTaskQueue.podspec'

  # Crypto
  pod 'SignalProtocolObjC', :path => 'Submodules/SignalProtocol-ObjC/SignalProtocolObjC.podspec'
  pod 'OTRKit', :path => 'Submodules/OTRKit/OTRKit.podspec'
  
  pod 'Mantle'

  #target 'GlacierNotifications'
end

target 'GlacierShare' do

  pod 'SQLCipher', :git => 'https://github.com/ChatSecure/sqlcipher.git', :branch => 'v4.3.0-catalyst'
  pod 'YapDatabase/SQLCipher', :path => 'Submodules/YapDatabase/YapDatabase.podspec'
  
  pod 'SAMKeychain', :git => 'https://github.com/afriedmanGlacier/SAMKeychain.git'
  pod 'XMPPFramework/Swift', :path => 'Submodules/XMPPFramework/XMPPFramework.podspec'
  pod 'BBlock', '~> 1.2.1'
  pod 'KVOController', '~> 1.2'
  pod 'CocoaLumberjack/Swift', '~> 3.4.2'
  pod 'MBProgressHUD', '~> 1.1'

  pod 'libsqlfs/SQLCipher', :path => 'Submodules/libsqlfs/libsqlfs.podspec'
  pod 'IOCipher/GCDWebServer', :path => 'Submodules/IOCipher/IOCipher.podspec'
  pod 'YapTaskQueue/SQLCipher', :path => 'Submodules/YapTaskQueue/YapTaskQueue.podspec'

  # Crypto
  pod 'SignalProtocolObjC', :path => 'Submodules/SignalProtocol-ObjC/SignalProtocolObjC.podspec'
  pod 'OTRKit', :path => 'Submodules/OTRKit/OTRKit.podspec'
  
  # pod 'GCDWebServer', '~> 3.4.2'
  pod 'Alamofire', '~> 5.0'
  pod 'Mantle'
end
