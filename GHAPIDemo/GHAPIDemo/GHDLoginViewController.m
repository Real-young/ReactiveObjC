//
//  GHDLoginViewController.m
//  GHAPIDemo
//
//  Created by Josh Abernathy on 3/5/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "GHDLoginViewController.h"
#import "GHDLoginView.h"
#import "GHGitHubClient.h"
#import "GHJSONRequestOperation.h"
#import "GHUserAccount.h"

@interface GHDLoginViewController ()
@property (nonatomic, assign) BOOL successHidden;
@property (nonatomic, assign) BOOL loginFailedHidden;
@property (nonatomic, assign) BOOL loginEnabled;
@property (nonatomic, assign) BOOL loggingIn;
@property (nonatomic, strong) RACAsyncCommand *loginCommand;
@property (nonatomic, strong) GHDLoginView *view;
@property (nonatomic, strong) GHUserAccount *userAccount;
@property (nonatomic, strong) GHGitHubClient *client;
@end


@implementation GHDLoginViewController

- (id)init {
	self = [super init];
	if(self == nil) return nil;
	
	self.loginFailedHidden = YES;
	self.successHidden = YES;
	self.loginEnabled = NO;
	self.loggingIn = NO;
	
	self.loginCommand = [RACAsyncCommand command];
	RACValue *loginResult = [self.loginCommand addOperationBlock:^{ return [self.client operationToLogin]; }];

	[self.loginCommand subscribeNext:^(id _) {
		self.userAccount = [GHUserAccount userAccountWithUsername:self.username password:self.password];
		self.client = [GHGitHubClient clientForUserAccount:self.userAccount];
		self.loggingIn = YES;
	}];
	
	[[[loginResult where:^(id x) {
		return [x hasError];
	}] select:^(id x) {
		return [x error];
	}] subscribeNext:^(id x) {
		self.loggingIn = NO;
		self.loginFailedHidden = NO;
		NSLog(@"error logging in: %@", x);
	}];
	
	[[loginResult where:^(id x) {
		return [x hasObject];
	}] subscribeNext:^(id _) {
		self.successHidden = NO;
		self.loggingIn = NO;
		[[self refreshAll] subscribeNext:^(id x) {
			NSLog(@"all the things: %@", x);
		}];
	}];
	
	[[RACSequence merge:[NSArray arrayWithObjects:RACObservable(self.username), RACObservable(self.password), nil]] subscribeNext:^(id _) {
		self.successHidden = self.loginFailedHidden = YES;
	}];
	
	[[RACSequence combineLatest:[NSArray arrayWithObjects:RACObservable(self.username), RACObservable(self.password), self.loginCommand.canExecuteValue, nil] reduce:^(NSArray *xs) {
		return [NSNumber numberWithBool:[[xs objectAtIndex:0] length] > 0 && [[xs objectAtIndex:1] length] > 0 && [[xs objectAtIndex:2] boolValue]];
	}] toObject:self keyPath:RACKVO(self.loginEnabled)];
	
	return self;
}


#pragma mark NSViewController

- (void)loadView {
	self.view = [GHDLoginView view];
	
	[self.view.usernameTextField bind:NSValueBinding toObject:self withKeyPath:RACKVO(self.username)];
	[self.view.passwordTextField bind:NSValueBinding toObject:self withKeyPath:RACKVO(self.password)];
	[self.view.successTextField bind:NSHiddenBinding toObject:self withKeyPath:RACKVO(self.successHidden)];
	[self.view.couldNotLoginTextField bind:NSHiddenBinding toObject:self withKeyPath:RACKVO(self.loginFailedHidden)];
	[self.view.loginButton bind:NSEnabledBinding toObject:self withKeyPath:RACKVO(self.loginEnabled)];
	[self.view.loggingInSpinner bind:NSHiddenBinding toObject:self withNegatedKeyPath:RACKVO(self.loggingIn)];
	
	[self.view.loggingInSpinner startAnimation:nil];
	
	[self.view.loginButton addCommand:self.loginCommand];
}


#pragma mark API

@synthesize username;
@synthesize password;
@dynamic view;
@synthesize successHidden;
@synthesize loginFailedHidden;
@synthesize loginCommand;
@synthesize loginEnabled;
@synthesize loggingIn;
@synthesize userAccount;
@synthesize client;

- (RACSequence *)refreshAll {
	RACAsyncCommand *getUserInfoCommand = [RACAsyncCommand command];
	getUserInfoCommand.queue = [[NSOperationQueue alloc] init];
	RACValue *getUserInfoResult = [getUserInfoCommand addOperationBlock:^{
		return [self.client operationToGetCurrentUserInfo];
	}];
	
	RACAsyncCommand *getReposCommand = [RACAsyncCommand command];
	getReposCommand.queue = [[NSOperationQueue alloc] init];
	RACValue *getReposResult = [getReposCommand addOperationBlock:^{
		return [self.client operationToGetCurrentUsersRepos];
	}];
	
	RACAsyncCommand *getOrgsCommand = [RACAsyncCommand command];
	getOrgsCommand.queue = [[NSOperationQueue alloc] init];
	RACValue *getOrgsResult = [getOrgsCommand addOperationBlock:^{ 
		return [self.client operationToGetCurrentUsersOrgs]; 
	}];
	
	RACSequence *results = [RACSequence zip:[NSArray arrayWithObjects:getUserInfoResult, getReposResult, getOrgsResult, nil] reduce:^(NSArray *xs) {
		RACMaybe *first = [xs objectAtIndex:0];
		RACMaybe *second = [xs objectAtIndex:1];
		RACMaybe *third = [xs objectAtIndex:2];
		return [NSArray arrayWithObjects:first.object ? : first.error, second.object ? : second.error, third.object ? : third.error, nil];
	}];

	[getUserInfoCommand execute:nil];
	[getReposCommand execute:nil];
	[getOrgsCommand execute:nil];
	
	return results;
}

@end