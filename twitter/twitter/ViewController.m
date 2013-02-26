//
//  ViewController.m
//  twitter
//
//  Created by Matt Vaznaian on 9/28/12.
//  Copyright (c) 2012 StackMob. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"
#import "StackMob.h"
#import <Accounts/Accounts.h>
#import <Twitter/Twitter.h>
#import "TWAPIManager.h"

@interface ViewController ()

@property (nonatomic, strong) ACAccountStore *accountStore;
@property (nonatomic, strong) TWAPIManager *apiManager;
@property (nonatomic, strong) NSArray *accounts;
@property (nonatomic, strong) UIButton *reverseAuthBtn;

- (void)loginWithTwitterToken:(id)oauthToken secret:(id)oauthTokenSecret;
- (void)obtainAccessToAccountsWithBlock:(void (^)(BOOL))block;
- (void)refreshTwitterAccounts:(id)sender;
- (void)performReverseAuth;

@end

@implementation ViewController

@synthesize managedObjectContext = _managedObjectContext;
@synthesize oauthToken = _oauthToken ;
@synthesize oauthTokenSecret = _oauthTokenSecret;

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshTwitterAccounts:self];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.managedObjectContext = [[self.appDelegate coreDataStore] contextForCurrentThread];
    _accountStore = [[ACAccountStore alloc] init];
    _apiManager = [[TWAPIManager alloc] init];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(refreshTwitterAccounts:)
     name:ACAccountStoreDidChangeNotification
     object:nil];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    
    [[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:ACAccountStoreDidChangeNotification
     object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (IBAction)loginUser:(id)sender {
    
    /*
     Initiate Twitter login.
     */
    [self performReverseAuth];
}

- (IBAction)checkStatus:(id)sender {
    
    NSLog(@"%@",[[self.appDelegate client] isLoggedIn] ? @"Logged In" : @"Logged Out");
    
    /*
     StackMob method to grab the currently logged in user's Twitter information.
     This assumes the user was logged in user Twitter credentials.
     */
    [[self.appDelegate client] getLoggedInUserTwitterInfoOnSuccess:^(NSDictionary *result) {
        NSLog(@"Logged In User Twitter Info, %@", result);
    } onFailure:^(NSError *error) {
        NSLog(@"error %@", error);
    }];
}

- (IBAction)logoutUser:(id)sender {
    
    /*
     StackMob method to logout the currently logged in user.
     */
    [[self.appDelegate client] logoutOnSuccess:^(NSDictionary *result) {
        NSLog(@"Logged out.");
    } onFailure:^(NSError *error) {
        NSLog(@"error %@", error);
    }];
}

- (void)loginWithTwitterToken:(id)oauthToken secret:(id)oauthTokenSecret {
    
    /*
     StackMob method to login with Twitter token and secret.
     */
    [[self.appDelegate client] loginWithTwitterToken:oauthToken twitterSecret:oauthTokenSecret onSuccess:^(NSDictionary *result) {
        NSLog(@"successful login with twitter: %@", result);
    } onFailure:^(NSError *error) {
        NSLog(@"login user fail: %@", error);
    }];
}

- (void)actionSheet:(UIActionSheet *)actionSheet
clickedButtonAtIndex:(NSInteger)buttonIndex
{
    /*
     This code is called after you select your Twitter account from the popup.
     It will grab your keys and perform a createUser / login with Twitter through
     StackMob.
     */
    if (buttonIndex != (actionSheet.numberOfButtons - 1)) {
        [_apiManager
         performReverseAuthForAccount:_accounts[buttonIndex]
         withHandler:^(NSData *responseData, NSError *error) {
             if (responseData) {
                 NSString *responseStr = [[NSString alloc]
                                          initWithData:responseData
                                          encoding:NSUTF8StringEncoding];
                 
                 NSArray *parts = [responseStr
                                   componentsSeparatedByString:@"&"];
                 
                 
                 NSLog(@"parts: %@", parts.description);
                 
                 // Get oauth_token
                 NSString *oauth_tokenKV = [parts objectAtIndex:0];
                 NSArray *oauth_tokenArray = [oauth_tokenKV componentsSeparatedByString:@"="];
                 NSString *oauth_token = [oauth_tokenArray objectAtIndex:1];
                 
                 // Get oauth_token_secret
                 NSString *oauth_token_secretKV = [parts objectAtIndex:1];
                 NSArray *oauth_token_secretArray = [oauth_token_secretKV componentsSeparatedByString:@"="];
                 NSString *oauth_token_secret = [oauth_token_secretArray objectAtIndex:1];
                 
                 // Get screen name
                 NSString *twitter_screen_nameKV = [parts objectAtIndex:3];
                 NSArray *twitter_screen_nameArray = [twitter_screen_nameKV componentsSeparatedByString:@"="];
                 NSString *twitter_screen_name = [twitter_screen_nameArray objectAtIndex:1];
                 
                 /*
                  Initiates creating a user on StackMob using Twitter credentials.
                  If one already exists, attempt login.
                  */
                 [[self.appDelegate client] createUserWithTwitterToken:oauth_token twitterSecret:oauth_token_secret username:twitter_screen_name onSuccess:^(NSDictionary *result) {
                     
                     NSLog(@"create user success");
                     _oauthToken = oauth_token;
                     _oauthTokenSecret = oauth_token_secret;
                     [self loginWithTwitterToken:oauth_token secret:oauth_token_secret];
                 } onFailure:^(NSError *error) {
                     
                     // If we get back a 401 it's probably because the user already exists, so attempt login.
                     if (error.code == 401) {
                         [self loginWithTwitterToken:oauth_token secret:oauth_token_secret];
                     }
                 }];
                 
             }
             else {
                 NSLog(@"Error!\n%@", [error localizedDescription]);
             }
         }];
    }
}



#pragma Twitter methods
- (void)obtainAccessToAccountsWithBlock:(void (^)(BOOL))block
{
    /*
     Get Twitter account info.
     */
    NSLog(@"obtain access");
    ACAccountType *twitterType = [_accountStore
                                  accountTypeWithAccountTypeIdentifier:
                                  ACAccountTypeIdentifierTwitter];
    
    ACAccountStoreRequestAccessCompletionHandler handler =
    ^(BOOL granted, NSError *error) {
        
        if (granted) {
            self.accounts = [_accountStore accountsWithAccountType:twitterType];
            NSLog(@"acct %@", self.accounts.description);
        } else {
            NSLog(@"error %@", error);
        }
        
        block(granted);
    };
    
    //  This method changed in iOS6.  If the new version isn't available, fall
    //  back to the original (which means that we're running on iOS5+).
    if ([_accountStore
         respondsToSelector:@selector(requestAccessToAccountsWithType:
                                      options:
                                      completion:)]) {
             
             [_accountStore requestAccessToAccountsWithType:twitterType
                                                    options:nil
                                                 completion:handler];
         }
    else {
        
        [_accountStore requestAccessToAccountsWithType:twitterType
                                 withCompletionHandler:handler];
    }
}


- (void)refreshTwitterAccounts:(id)sender
{
    /* 
     Initiate get Twitter account info method.
     */
    //  Get access to the user's Twitter account(s)
    [self obtainAccessToAccountsWithBlock:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                //_reverseAuthBtn.enabled = YES;
            }
            else {
                NSLog(@"You were not granted access to the Twitter accounts.");
            }
        });
    }];
}




- (void)performReverseAuth
{
    /*
     Initiates a popup for you to select the Twitter account to sign in with.
     */
    if ([TWAPIManager isLocalTwitterAccountAvailable]) {
        UIActionSheet *sheet = [[UIActionSheet alloc]
                                initWithTitle:@"Choose an Account"
                                delegate:self
                                cancelButtonTitle:nil
                                destructiveButtonTitle:nil
                                otherButtonTitles:nil];
        NSLog(@"Local available ");
        for (ACAccount *acct in _accounts) {
            [sheet addButtonWithTitle:acct.username];
        }
        
        [sheet addButtonWithTitle:@"Cancel"];
        [sheet setDestructiveButtonIndex:[_accounts count]];
        [sheet showInView:self.view];
    }
    else {
        UIAlertView *alert = [[UIAlertView alloc]
                              initWithTitle:@"No Accounts"
                              message:@"Please configure a Twitter "
                              "account in Settings.app"
                              delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil];
        [alert show];
    }
}

@end
