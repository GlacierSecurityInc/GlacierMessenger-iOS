# [Glacier](http://www.glaciersecurity.com) Messenger

[Glacier](http://www.glaciersecurity.com) Messenger is a free and open source [XMPP](https://en.wikipedia.org/wiki/XMPP) messaging client for iOS that is based on [ChatSecure](https://chatsecure.org) and that integrates [OMEMO](https://en.wikipedia.org/wiki/OMEMO) encrypted messaging support.

## Cost

Glacier Messenger is free to download and use (thanks to ChatSecure and the GPLv3 license). However, the changes made to the ChatSecure base product were intended to optimize Glacier Messenger for use with the full set of Glacier Security services, so Glacier Messenger may not be the best choice for those looking for a one size fits all solution. For an iOS messaging client that works with most modern XMPP servers, see [ChatSecure](https://chatsecure.org).

[Glacier Security](http://www.glaciersecurity.com) is a full-service provider of secure, end-to-end encrypted, and anonymous communication solutions for enterprise and government. Our cloud based immutable infrastructure is launched automatically for each customer leveraging concepts of Department of Homeland Security’s Moving Target Defense project. Glacier controls change across multiple system dimensions in order to increase uncertainty for attackers, reduce their window of opportunity, increase the costs of their attack efforts, and keep end user devices anonymous.

Because Glacier services typically run within a private network, numerous assumptions were purposefully made to optimize and simplify usage for this specific scenario. Some of these design choices are not recommended for use outside of a Glacier network.


## Build Instructions

Note: Many of the instructions, directories, and files reference ChatSecure because Glacier Messenger is based on [ChatSecure-iOS](https://github.com/ChatSecure/ChatSecure-iOS).

You'll need [CocoaPods](http://cocoapods.org) installed for our dependencies. 
    
    $ gem install cocoapods
    
Download the source code and **don't forget** to pull down all of the submodules as well. 

    $ git clone https://git@bitbucket.org/glaciersec/ios-messenger.git
    $ cd ios-messenger/
    $ git submodule update --init --recursive
    
Now you'll need to build the dependencies. There are some work arounds included for current build gotchas that will be fixed in the future; the "normal" build instructions wouldn't require some of these steps.
    
    $ bash ./Submodules/OTRKit/scripts/build-all.sh
    $ pod repo update
    - Remove these lines from Submodules/OTRKit/OTRKit.podspec because we are building for iOS. You may or may not need to do this depending what OS version you are using to build, but the macOS lines can give errors:
        export PLATFORM_TARGET="macOS"
        bash ./scripts/build-all.sh
    - Change the first s.osx.frameworks to s.ios.frameworks
    - Remove the rest of the lines that begin with s.osx.frameworks
    $ pod install
    
Next you'll need to create your own version of environment-specific data. Make a copy of `Secrets-template.plist` as `Secrets.plist`:

    $ cp OTRResources/Secrets-template.plist OTRResources/Secrets.plist
    
Glacier Messenger currently uses AWS Cognito to facilitate single signon model across the platform of Glacier applications. As part of this, the AWS Cognito and S3 IDs need to be added to the Secrets.plist file

You'll need to manually change the Team ID under Project -> Targets -> ChatSecure -> Signing. The old .xcconfig method doesn't seem to work well anymore.

Open `Messenger.xcworkspace` in Xcode. Before building, there is an error in the SQLite.swift pod that needs to be fixed. Unfortunately the fix requires making a change to the pod which requires unlocking the file. The change is to SQLite.swift/standard/fts3_tokenizer.h. 

    $ On line 27, change #import "sqlite3.h" to #import <sqlite3.h>. 

Then, build in XCode.

*Note*: **Don't open the `.xcodeproj`** because we use Cocoapods!


