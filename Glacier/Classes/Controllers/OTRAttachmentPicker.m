//
//  OTRAttachmentPicker.m
//  ChatSecure
//
//  Created by David Chiles on 1/16/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

#import "OTRAttachmentPicker.h"

@import MobileCoreServices;
#import "OTRUtilities.h"
#import "OTRStrings.h"
#import "UIActionSheet+ChatSecure.h"

#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

@interface OTRAttachmentPicker () <UINavigationControllerDelegate, PHPickerViewControllerDelegate>

@property (nonatomic, strong) UIImagePickerController *imagePickerController;
@property (nonatomic, strong) UIDocumentPickerViewController *documentPicker;


@end

@implementation OTRAttachmentPicker

- (instancetype)initWithParentViewController:(UIViewController<UIPopoverPresentationControllerDelegate> *)viewController delegate:(id<OTRAttachmentPickerDelegate>)delegate
{
    if (self = [super init]) {
        _parentViewController = viewController;
        _delegate = delegate;
    }
    return self;
}

- (void)showAlertControllerFromSourceView:(UIView *)senderView withCompletion:(void (^)(void))completion
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        UIAlertAction *takePhotoAction = [UIAlertAction actionWithTitle:USE_CAMERA_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {            
            [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
        }];
        [alertController addAction:takePhotoAction];
    }
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        UIAlertAction *openLibraryAction = [UIAlertAction actionWithTitle:PHOTO_LIBRARY_STRING() style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showImagePickerForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
        }];
        [alertController addAction:openLibraryAction];
    }
    
    UIAlertAction *filePickerAction = [UIAlertAction actionWithTitle:@"Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showFilePicker];
    }];
    if (![senderView isKindOfClass:[UITableViewCell class]]) {
        [alertController addAction:filePickerAction];
    }
    
    UIAlertAction *shareLocationAction = [UIAlertAction actionWithTitle:@"Share Location" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showShareLocation];
    }];
    if (![senderView isKindOfClass:[UITableViewCell class]]) {
        [alertController addAction:shareLocationAction];
    }
    
    if ([self.delegate respondsToSelector:@selector(attachmentPicker:addAdditionalOptions:)]) {
        [self.delegate attachmentPicker:self addAdditionalOptions:alertController];
    }
    
    UIAlertAction *cancelAlertAction = [UIAlertAction actionWithTitle:CANCEL_STRING() style:UIAlertActionStyleCancel handler:nil];
    
    [alertController addAction:cancelAlertAction];
    
    alertController.popoverPresentationController.delegate = self.parentViewController;
    if (!senderView) {
        senderView = self.parentViewController.view;
    }
    alertController.popoverPresentationController.sourceView = senderView;
    alertController.popoverPresentationController.sourceRect = senderView.bounds;
    
    [self.parentViewController presentViewController:alertController animated:YES completion:completion];
}

- (void)showShareLocation
{
    NSURL *shareURL = [NSURL fileURLWithPath:@"http://google.com"];
    if ([self.delegate respondsToSelector:@selector(attachmentPicker:shareLocationButtonPressed:)]) {
        [self.delegate attachmentPicker:self shareLocationButtonPressed:shareURL];
    }
    [self.imagePickerController dismissViewControllerAnimated:YES completion:nil];
    self.imagePickerController = nil;
}

- (void)showFilePicker 
{
    NSArray *types = @[@"com.apple.iwork.pages.pages", @"com.apple.iwork.numbers.numbers", @"com.apple.iwork.keynote.key",@"public.image", @"com.apple.application", @"public.item",@"public.data", @"public.content", @"public.audiovisual-content", @"public.movie", @"public.audiovisual-content", @"public.video", @"public.text", @"public.data", @"public.composite-content"];
    
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
    documentPicker.modalPresentationStyle = UIModalPresentationCurrentContext;
    documentPicker.delegate = self;
    
    self.documentPicker = documentPicker;
    [self.parentViewController presentViewController:self.documentPicker animated:YES completion:nil];
    
    /*UIDocumentPickerViewController *documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.iwork.pages.pages", "com.apple.iwork.numbers.numbers", "com.apple.iwork.keynote.key","public.image", "com.apple.application", "public.item","public.data", "public.content", "public.audiovisual-content", "public.movie", "public.audiovisual-content", "public.video", "public.text", "public.data", "public.composite-content", "public.text"], in: .import)
      NSArray *types = @[(NSString*)kUTTypeImage,(NSString*)kUTTypeSpreadsheet,(NSString*)kUTTypePresentation,(NSString*)kUTTypeDatabase,(NSString*)kUTTypeFolder,(NSString*)kUTTypeZipArchive,(NSString*)kUTTypeVideo];
    
    //UTI: com.adobe.pdf
    //conforms to: public.data, public.composite-content
    */
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    if ([self.delegate respondsToSelector:@selector(attachmentPicker:gotFileURL:)]) {
        [self.delegate attachmentPicker:self gotFileURL:url];
    }
    [controller dismissViewControllerAnimated:YES completion:nil];
    self.documentPicker = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
    self.documentPicker = nil;
}


- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType
{
    if (sourceType != UIImagePickerControllerSourceTypeCamera){ 
        if (@available(iOS 14.0, *)) {
            PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
            config.selectionLimit = 5;
        
            if ([self.delegate respondsToSelector:@selector(attachmentPicker:preferredMediaTypesForSource:)] && ([self.delegate attachmentPicker:self preferredMediaTypesForSource:sourceType].count == 1)) { //assume avatar only
                config.filter = [PHPickerFilter imagesFilter];
                config.selectionLimit = 1;
            }
            
            config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
            PHPickerViewController *pickerViewController = [[PHPickerViewController alloc] initWithConfiguration:config];
            pickerViewController.modalPresentationStyle = UIModalPresentationCurrentContext;
            pickerViewController.delegate = self;
            [self.parentViewController presentViewController:pickerViewController animated:YES completion:nil];
            return;
        }
    }
    
    UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
    imagePickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    imagePickerController.sourceType = sourceType;
    NSArray* availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:sourceType];
    if ([self.delegate respondsToSelector:@selector(attachmentPicker:preferredMediaTypesForSource:)])  {
        NSArray *preferredMediaTypes = [self.delegate attachmentPicker:self preferredMediaTypesForSource:sourceType];
        if (preferredMediaTypes) {
            NSMutableSet *availableSet = [NSMutableSet setWithArray:availableMediaTypes];
            [availableSet intersectSet:[NSSet setWithArray:preferredMediaTypes]];
            availableMediaTypes = [availableSet allObjects];
        } else {
            availableMediaTypes = @[];
        }
    }
    imagePickerController.mediaTypes = availableMediaTypes;
    imagePickerController.delegate = self;
    
    self.imagePickerController = imagePickerController;
    [self.parentViewController presentViewController:self.imagePickerController animated:YES completion:nil];
}

#pragma - mark PHPickerViewControllerDelegate
-(void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)){
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    NSString *imageString = (NSString *)kUTTypeImage;
    NSString *videoString = (NSString *)kUTTypeVideo;
    NSString *movieString = (NSString *)kUTTypeMovie;
    
    for (PHPickerResult *result in results)
    {
        if ([result.itemProvider hasItemConformingToTypeIdentifier:imageString]) {
            [result.itemProvider loadFileRepresentationForTypeIdentifier:imageString completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                if ([self.delegate respondsToSelector:@selector(attachmentPicker:gotPhoto:withInfo:)]) {
                    NSData *imageData = [NSData dataWithContentsOfURL:url];
                    UIImage* image = [[UIImage alloc] initWithData:imageData];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate attachmentPicker:self gotPhoto:image withInfo:@{}];
                    });
                }
            }];
        } else if ([result.itemProvider hasItemConformingToTypeIdentifier:videoString]) {
            [result.itemProvider loadFileRepresentationForTypeIdentifier:videoString completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                [self handleVideoPicked:url];
            }];
        } else if ([result.itemProvider hasItemConformingToTypeIdentifier:movieString]) {
            [result.itemProvider loadFileRepresentationForTypeIdentifier:movieString completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                [self handleVideoPicked:url];
            }];
        }
    }
}
 
- (void) handleVideoPicked:(NSURL *)url {
    if ([self.delegate respondsToSelector:@selector(attachmentPicker:gotVideoURL:)]) {
        NSError *error;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *temporaryPath = NSTemporaryDirectory();
        NSString *tmppath = [temporaryPath stringByAppendingPathComponent:url.lastPathComponent];
        
        if ([fileManager fileExistsAtPath:tmppath]) {
            [fileManager removeItemAtPath:tmppath error:&error];
        }
        
        if ([fileManager copyItemAtPath:url.path toPath:tmppath error:&error]){
            NSURL *newurl = [NSURL fileURLWithPath:tmppath];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate attachmentPicker:self gotVideoURL:newurl];
            });
        }
    }
}

#pragma - mark UIImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    NSString *imageString = (NSString *)kUTTypeImage;
    NSString *videoString = (NSString *)kUTTypeVideo;
    NSString *movieString = (NSString *)kUTTypeMovie;
    
    if ([mediaType isEqualToString:imageString]) {
        UIImage *editedImage = (UIImage *)info[UIImagePickerControllerEditedImage];
        UIImage *originalImage = (UIImage *)info[UIImagePickerControllerOriginalImage];
        UIImage *finalImage = nil;
        
        if (editedImage) {
            finalImage = editedImage;
        }
        else if (originalImage) {
            finalImage = originalImage;
        }
        
        if ([self.delegate respondsToSelector:@selector(attachmentPicker:gotPhoto:withInfo:)]) {
            [self.delegate attachmentPicker:self gotPhoto:finalImage withInfo:info];
        }
        
        [picker dismissViewControllerAnimated:YES completion:nil];
        self.imagePickerController = nil;
    }
    else if ([mediaType isEqualToString:videoString] || [mediaType isEqualToString:movieString]) {
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        if ([self.delegate respondsToSelector:@selector(attachmentPicker:gotVideoURL:)]) {
            [self.delegate attachmentPicker:self gotVideoURL:videoURL];
        }
        [picker dismissViewControllerAnimated:YES completion:nil];
        self.imagePickerController = nil;
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.imagePickerController = nil;
}

@end
