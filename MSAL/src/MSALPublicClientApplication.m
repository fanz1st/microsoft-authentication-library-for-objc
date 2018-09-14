//------------------------------------------------------------------------------
//
// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//------------------------------------------------------------------------------

#import "MSALPublicClientApplication+Internal.h"
#import "MSALError.h"
#import "MSALError_Internal.h"
#import "MSALInteractiveRequest.h"
#import "MSALSilentRequest.h"
#import "MSALRequestParameters.h"
#import "MSALUIBehavior_Internal.h"
#import "MSALURLSession.h"

#import "MSALTelemetryApiId.h"
#import "MSALTelemetry.h"
#if TARGET_OS_IPHONE
#import "MSIDKeychainTokenCache.h"
#endif
#import "MSIDMacTokenCache.h"
#import "MSIDLegacyTokenCacheAccessor.h"
#import "MSIDDefaultTokenCacheAccessor.h"
#import "MSIDAccount.h"
#import "NSURL+MSIDExtensions.h"
#import "MSALAccount+Internal.h"
#import "MSIDRefreshToken.h"
#import "MSALIdToken.h"
#import "MSIDAADV2IdTokenClaims.h"
#import "MSALErrorConverter.h"
#import "MSALAccountId.h"
#import "MSALAuthority.h"
#import "MSALAuthority_Internal.h"
#import "MSIDAADV2Oauth2Factory.h"
#import "MSIDAADAuthority.h"
#import "MSIDAuthorityFactory.h"
#import "MSALAADAuthority.h"

static NSString *const s_defaultAuthorityUrlString = @"https://login.microsoftonline.com/common";
static NSString *s_defaultKeychainGroup;

#import "MSIDAuthority.h"

#import "MSIDAADV2Oauth2Factory.h"
#import "MSALRedirectUriVerifier.h"

#import "MSIDWebviewAuthorization.h"
#import "MSIDWebviewSession.h"

@interface MSALPublicClientApplication()
{
    WKWebView *_customWebview;
    NSString *_defaultKeychainGroup;
}

@property (nonatomic) MSIDDefaultTokenCacheAccessor *tokenCache;
#if TARGET_OS_IPHONE
@property (nonatomic, readwrite) NSString *keychainGroup;
#endif

@end

@implementation MSALPublicClientApplication

+ (void)initialize
{
#if TARGET_OS_IPHONE
    s_defaultKeychainGroup = MSIDKeychainTokenCache.defaultKeychainGroup;
#else
    s_defaultKeychainGroup = nil;
#endif
}

// Make sure scheme is registered in info.plist
// If broker is enabled, make sure redirect uri has bundle id in it
// If no redirect uri is provided, generate a default one, which is compatible with broker if broker is enabled
- (BOOL)verifyRedirectUri:(NSString *)redirectUriString
                 clientId:(NSString *)clientId
                    error:(NSError * __autoreleasing *)error
{
    NSURL *generatedRedirectUri = [MSALRedirectUriVerifier generateRedirectUri:redirectUriString
                                                                      clientId:clientId
                                                                 brokerEnabled:NO
                                                                         error:error];

    if (!generatedRedirectUri)
    {
        return NO;
    }

    _redirectUri = generatedRedirectUri.absoluteString;

    return [MSALRedirectUriVerifier verifyRedirectUri:generatedRedirectUri
                                        brokerEnabled:NO
                                                error:error];
}

- (id)initWithClientId:(NSString *)clientId
                 error:(NSError * __autoreleasing *)error
{
    return [self initWithClientId:clientId
                    keychainGroup:s_defaultKeychainGroup
                        authority:nil
                      redirectUri:nil
                            error:error];
}

- (id)initWithClientId:(NSString *)clientId
             authority:(MSALAuthority *)authority
                 error:(NSError **)error
{
    return [self initWithClientId:clientId
                    keychainGroup:s_defaultKeychainGroup
                        authority:authority
                      redirectUri:nil
                            error:error];
}

- (id)initWithClientId:(NSString *)clientId
             authority:(MSALAuthority *)authority
           redirectUri:(NSString *)redirectUri
                 error:(NSError **)error
{
    return [self initWithClientId:clientId
                    keychainGroup:s_defaultKeychainGroup
                        authority:authority
                      redirectUri:redirectUri
                            error:error];
}

#if TARGET_OS_IPHONE

- (id)initWithClientId:(NSString *)clientId
         keychainGroup:(NSString *)keychainGroup
                 error:(NSError * __autoreleasing *)error
{
    return [self initWithClientId:clientId
                    keychainGroup:keychainGroup
                        authority:nil
                      redirectUri:nil
                            error:error];
}

- (id)initWithClientId:(NSString *)clientId
         keychainGroup:(NSString *)keychainGroup
             authority:(MSALAuthority *)authority
                 error:(NSError * __autoreleasing *)error
{
    return [self initWithClientId:clientId
                    keychainGroup:keychainGroup
                        authority:authority
                      redirectUri:nil
                            error:error];
}

#endif

- (id)initWithClientId:(NSString *)clientId
         keychainGroup:(NSString *)keychainGroup
             authority:(MSALAuthority *)authority
           redirectUri:(NSString *)redirectUri
                 error:(NSError * __autoreleasing *)error
{
    if (!(self = [super init]))
    {
        return nil;
    }

    if ([NSString msidIsStringNilOrBlank:clientId])
    {
        MSAL_ERROR_PARAM(nil, MSALErrorInvalidParameter, @"clientId is a required parameter and must not be nil or empty.");
        return nil;
    }

    _clientId = clientId;

    if (authority)
    {
        _authority = authority;
    }
    else
    {
        // TODO: Rationalize our default authority behavior (#93)
        NSURL *authorityURL = [NSURL URLWithString:s_defaultAuthorityUrlString];
        _authority = [[MSALAADAuthority alloc] initWithURL:authorityURL context:nil error:error];
    }

    BOOL redirectUriValid = [self verifyRedirectUri:redirectUri clientId:clientId error:error];

    if (!redirectUriValid) return nil;

#if TARGET_OS_IPHONE
    // Optional Paramater
    _keychainGroup = keychainGroup;

    MSIDKeychainTokenCache *dataSource;
    if (_keychainGroup == nil)
    {
        _keychainGroup = [[NSBundle mainBundle] bundleIdentifier];
    }
    
    dataSource = [[MSIDKeychainTokenCache alloc] initWithGroup:_keychainGroup];
    
    MSIDOauth2Factory *factory = [MSIDAADV2Oauth2Factory new];
    
    MSIDLegacyTokenCacheAccessor *legacyAccessor = [[MSIDLegacyTokenCacheAccessor alloc] initWithDataSource:dataSource otherCacheAccessors:nil factory:factory];
    MSIDDefaultTokenCacheAccessor *defaultAccessor = [[MSIDDefaultTokenCacheAccessor alloc] initWithDataSource:dataSource otherCacheAccessors:@[legacyAccessor] factory:factory];
    
    self.tokenCache = defaultAccessor;
    
    _webviewType = MSALWebviewTypeDefault;
    
#else
    __auto_type dataSource = MSIDMacTokenCache.defaultCache;

    MSIDDefaultTokenCacheAccessor *defaultAccessor = [[MSIDDefaultTokenCacheAccessor alloc] initWithDataSource:dataSource otherCacheAccessors:nil factory:[MSIDAADV2Oauth2Factory new]];
    self.tokenCache = defaultAccessor;
    _webviewType = MSALWebviewTypeWKWebView;
    
#endif
    
    _validateAuthority = YES;
    _extendedLifetimeEnabled = NO;
    
    _sliceParameters = [MSALPublicClientApplication defaultSliceParameters];
    
    
    return self;
}


- (NSArray <MSALAccount *> *)accounts:(NSError * __autoreleasing *)error
{
    NSError *msidError = nil;
    __auto_type host = self.authority.msidAuthority.environment;
    __auto_type msidAccounts = [self.tokenCache allAccountsForEnvironment:host
                                                                 clientId:self.clientId
                                                                 familyId:nil
                                                                  context:nil
                                                                    error:&msidError];

    if (msidError)
    {
        *error = msidError;
        return nil;
    }

    NSMutableSet *msalAccounts = [NSMutableSet new];

    for (MSIDAccount *msidAccount in msidAccounts)
    {
        MSALAccount *msalAccount = [[MSALAccount alloc] initWithMSIDAccount:msidAccount];

        if (msalAccount)
        {
            [msalAccounts addObject:msalAccount];
        }
    }

    return [msalAccounts allObjects];
}

- (MSALAccount *)accountForHomeAccountId:(NSString *)homeAccountId
                                   error:(NSError * __autoreleasing *)error
{
    NSArray<MSALAccount *> *accounts = [self accounts:error];

    for (MSALAccount *account in accounts)
    {
        if ([account.homeAccountId.identifier isEqualToString:homeAccountId])
        {
            return account;
        }
    }

    return nil;
}

- (MSALAccount *)accountForUsername:(NSString *)username
                              error:(NSError * __autoreleasing *)error
{
    NSArray<MSALAccount *> *accounts = [self accounts:error];

    for (MSALAccount *account in accounts)
    {
        if ([account.username isEqualToString:username])
        {
            return account;
        }
    }

    return nil;
}

#pragma SafariViewController Support

#if TARGET_OS_IPHONE
+ (BOOL)handleMSALResponse:(NSURL *)response
{
    return [MSIDWebviewAuthorization handleURLResponseForSystemWebviewController:response];
}
#endif

+ (void)cancelCurrentWebAuthSession
{
    [MSIDWebviewAuthorization cancelCurrentSession];
}

#pragma mark -
#pragma mark acquireToken

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:nil
                        account:nil
                      loginHint:nil
                     uiBehavior:MSALUIBehaviorDefault
           extraQueryParameters:nil
                         claims:nil
                      authority:nil
                  correlationId:nil
                          apiId:MSALTelemetryApiIdAcquire
                completionBlock:completionBlock];
}

#pragma mark -
#pragma mark Login Hint

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
                    loginHint:(NSString *)loginHint
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:nil
                        account:nil
                      loginHint:loginHint
                     uiBehavior:MSALUIBehaviorDefault
           extraQueryParameters:nil
                         claims:nil
                      authority:nil
                  correlationId:nil
                          apiId:MSALTelemetryApiIdAcquireWithHint
                completionBlock:completionBlock];
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
                    loginHint:(NSString *)loginHint
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:nil
                        account:nil
                      loginHint:loginHint
                     uiBehavior:uiBehavior
           extraQueryParameters:extraQueryParameters
                         claims:nil
                      authority:nil
                  correlationId:nil
                          apiId:MSALTelemetryApiIdAcquireWithHintBehaviorAndParameters
                completionBlock:completionBlock];
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
         extraScopesToConsent:(NSArray<NSString *> *)extraScopesToConsent
                    loginHint:(NSString *)loginHint
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
                    authority:(MSALAuthority *)authority
                correlationId:(NSUUID *)correlationId
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:extraScopesToConsent
                        account:nil
                      loginHint:loginHint
                     uiBehavior:uiBehavior
           extraQueryParameters:extraQueryParameters
                         claims:nil
                      authority:authority
                  correlationId:correlationId
                          apiId:MSALTelemetryApiIdAcquireWithHintBehaviorParametersAuthorityAndCorrelationId
                completionBlock:completionBlock];
}

#pragma mark -
#pragma mark Account


- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
                      account:(MSALAccount *)account
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:nil
                        account:account
                      loginHint:nil
                     uiBehavior:MSALUIBehaviorDefault
           extraQueryParameters:nil
                         claims:nil
                      authority:nil
                  correlationId:nil
                          apiId:MSALTelemetryApiIdAcquireWithUserBehaviorAndParameters
                completionBlock:completionBlock];
    
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
                      account:(MSALAccount *)account
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:nil
                        account:account
                      loginHint:nil
                     uiBehavior:uiBehavior
           extraQueryParameters:extraQueryParameters
                         claims:nil
                      authority:nil
                  correlationId:nil
                          apiId:MSALTelemetryApiIdAcquireWithUserBehaviorAndParameters
                completionBlock:completionBlock];
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
         extraScopesToConsent:(NSArray<NSString *> *)extraScopesToConsent
                      account:(MSALAccount *)account
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
                    authority:(MSALAuthority *)authority
                correlationId:(NSUUID *)correlationId
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:extraScopesToConsent
                        account:account
                      loginHint:nil
                     uiBehavior:uiBehavior
           extraQueryParameters:extraQueryParameters
                         claims:nil
                      authority:authority
                  correlationId:correlationId
                          apiId:MSALTelemetryApiIdAcquireWithUserBehaviorParametersAuthorityAndCorrelationId
                completionBlock:completionBlock];
    
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
         extraScopesToConsent:(NSArray<NSString *> *)extraScopesToConsent
                      account:(MSALAccount *)account
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
                       claims:(NSString *)claims
                    authority:(MSALAuthority *)authority
                correlationId:(NSUUID *)correlationId
              completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenForScopes:scopes
           extraScopesToConsent:extraScopesToConsent
                        account:account
                      loginHint:nil
                     uiBehavior:uiBehavior
           extraQueryParameters:extraQueryParameters
                         claims:claims
                      authority:authority
                  correlationId:correlationId
                          apiId:MSALTelemetryApiIdAcquireWithUserBehaviorParametersAuthorityAndCorrelationId
                completionBlock:completionBlock];
    
}

#pragma mark -
#pragma mark Silent

- (void)acquireTokenSilentForScopes:(NSArray<NSString *> *)scopes
                            account:(MSALAccount *)account
                    completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenSilentForScopes:scopes
                              account:account
                            authority:nil
                         forceRefresh:NO
                        correlationId:nil
                                apiId:MSALTelemetryApiIdAcquireSilentWithUser
                      completionBlock:completionBlock];
}

- (void)acquireTokenSilentForScopes:(NSArray<NSString *> *)scopes
                            account:(MSALAccount *)account
                          authority:(MSALAuthority *)authority
                    completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenSilentForScopes:scopes
                              account:account
                            authority:authority
                         forceRefresh:NO
                        correlationId:nil
                                apiId:MSALTelemetryApiIdAcquireSilentWithUserAndAuthority
                      completionBlock:completionBlock];
}

- (void)acquireTokenSilentForScopes:(NSArray<NSString *> *)scopes
                            account:(MSALAccount *)account
                          authority:(MSALAuthority *)authority
                       forceRefresh:(BOOL)forceRefresh
                      correlationId:(NSUUID *)correlationId
                    completionBlock:(MSALCompletionBlock)completionBlock
{
    [self acquireTokenSilentForScopes:scopes
                              account:account
                            authority:authority
                         forceRefresh:forceRefresh
                        correlationId:correlationId
                                apiId:MSALTelemetryApiIdAcquireSilentWithUserAuthorityForceRefreshAndCorrelationId
                      completionBlock:completionBlock];
}


#pragma mark -
#pragma mark - private methods

+ (void)logOperation:(NSString *)operation
              result:(MSALResult *)result
               error:(NSError *)error
             context:(id<MSALRequestContext>)ctx
{
    if (error)
    {
        NSString *errorDescription = error.userInfo[MSALErrorDescriptionKey];
        errorDescription = errorDescription ? errorDescription : @"";
        MSID_LOG_ERROR(ctx, @"%@ returning with error: (%@, %ld)", operation, error.domain, (long)error.code);
        MSID_LOG_ERROR_PII(ctx, @"%@ returning with error: (%@, %ld) %@", operation, error.domain, (long)error.code, errorDescription);
    }
    
    if (result)
    {
        NSString *hashedAT = [result.accessToken msidTokenHash];
        MSID_LOG_INFO(ctx, @"%@ returning with at: %@ scopes:%@ expiration:%@", operation, _PII_NULLIFY(hashedAT), _PII_NULLIFY(result.scopes), result.expiresOn);
        MSID_LOG_INFO_PII(ctx, @"%@ returning with at: %@ scopes:%@ expiration:%@", operation, hashedAT, result.scopes, result.expiresOn);
    }
}

- (void)acquireTokenForScopes:(NSArray<NSString *> *)scopes
         extraScopesToConsent:(NSArray<NSString *> *)extraScopesToConsent
                      account:(MSALAccount *)account
                    loginHint:(NSString *)loginHint
                   uiBehavior:(MSALUIBehavior)uiBehavior
         extraQueryParameters:(NSDictionary <NSString *, NSString *> *)extraQueryParameters
                       claims:(NSString *)claims
                    authority:(MSALAuthority *)authority
                correlationId:(NSUUID *)correlationId
                        apiId:(MSALTelemetryApiId)apiId
              completionBlock:(MSALCompletionBlock)completionBlock
{
    MSALRequestParameters *params = [MSALRequestParameters new];

    params.msidOAuthFactory = [MSIDAADV2Oauth2Factory new];
    params.correlationId = correlationId ? correlationId : [NSUUID new];
    params.logComponent = _component;
    params.apiId = apiId;
    params.account = account;
    params.validateAuthority = _validateAuthority;
    params.sliceParameters = _sliceParameters;
    
    MSID_LOG_INFO(params,
             @"-[MSALPublicClientApplication acquireTokenForScopes:%@\n"
              "                               extraScopesToConsent:%@\n"
              "                                            account:%@\n"
              "                                          loginHint:%@\n"
              "                                         uiBehavior:%@\n"
              "                               extraQueryParameters:%@\n"
              "                                          authority:%@\n"
              "                                      correlationId:%@]",
             _PII_NULLIFY(scopes), _PII_NULLIFY(extraScopesToConsent), _PII_NULLIFY(account.homeAccountId), _PII_NULLIFY(loginHint), MSALStringForMSALUIBehavior(uiBehavior), extraQueryParameters, _PII_NULLIFY(authority), correlationId);
    MSID_LOG_INFO_PII(params,
                 @"-[MSALPublicClientApplication acquireTokenForScopes:%@\n"
                  "                               extraScopesToConsent:%@\n"
                  "                                            account:%@\n"
                  "                                          loginHint:%@\n"
                  "                                         uiBehavior:%@\n"
                  "                               extraQueryParameters:%@\n"
                  "                                          authority:%@\n"
                  "                                      correlationId:%@]",
                 scopes, extraScopesToConsent, account.homeAccountId, loginHint, MSALStringForMSALUIBehavior(uiBehavior), extraQueryParameters, authority, correlationId);
    
    MSALCompletionBlock block = ^(MSALResult *result, NSError *error)
    {
        [MSALPublicClientApplication logOperation:@"acquireToken" result:result error:error context:params];
        completionBlock(result, error);
    };
    
    [params setScopesFromArray:scopes];
    params.loginHint = loginHint;
    params.extraQueryParameters = extraQueryParameters;
    params.claims = [NSString msidIsStringNilOrBlank:claims] ? nil : claims;
    params.unvalidatedAuthority = authority.msidAuthority ?: _authority.msidAuthority;
    params.redirectUri = _redirectUri;
    params.clientId = _clientId;
    params.urlSession = [MSALURLSession createMSALSession:params];
    params.webviewType = _webviewType;
    params.customWebview = _customWebview;

    NSError *error = nil;

    MSALInteractiveRequest *request =
    [[MSALInteractiveRequest alloc] initWithParameters:params
                                      extraScopesToConsent:extraScopesToConsent
                                              behavior:uiBehavior
                                            tokenCache:self.tokenCache
                                                 error:&error];
    if (!request)
    {
        [params.urlSession invalidateAndCancel];
        block(nil, error);
        return;
    }
    
    [request run:^(MSALResult *result, NSError *error) {
        [params.urlSession invalidateAndCancel];
        block(result, error);
    }];
}

- (void)acquireTokenSilentForScopes:(NSArray<NSString *> *)scopes
                            account:(MSALAccount *)account
                          authority:(MSALAuthority *)authority
                       forceRefresh:(BOOL)forceRefresh
                      correlationId:(NSUUID *)correlationId
                              apiId:(MSALTelemetryApiId)apiId
                    completionBlock:(MSALCompletionBlock)completionBlock
{
    MSIDAuthority *msidAuthority = authority.msidAuthority;

    if (!msidAuthority)
    {
        msidAuthority = self.authority.msidAuthority;
    }

    /*
     In the acquire token silent call we assume developer wants to get access token for account's home tenant,
     if authority is a common, organizations or consumers authority.
     */
    __auto_type authorityFactory = [MSIDAuthorityFactory new];
    msidAuthority = [authorityFactory authorityFromUrl:msidAuthority.url rawTenant:account.homeAccountId.tenantId context:nil error:nil];

    MSALRequestParameters* params = [MSALRequestParameters new];
    params.msidOAuthFactory = [MSIDAADV2Oauth2Factory new];
    params.correlationId = correlationId ? correlationId : [NSUUID new];
    params.account = account;
    params.apiId = apiId;
    params.validateAuthority = _validateAuthority;
    params.extendedLifetimeEnabled = _extendedLifetimeEnabled;
    params.sliceParameters = _sliceParameters;
    
    [params setScopesFromArray:scopes];
    
    MSID_LOG_INFO(params,
             @"-[MSALPublicClientApplication acquireTokenSilentForScopes:%@\n"
              "                                                  account:%@\n"
              "                                             forceRefresh:%@\n"
              "                                            correlationId:%@\n]",
             _PII_NULLIFY(scopes), _PII_NULLIFY(account), forceRefresh ? @"Yes" : @"No", correlationId);
    
    
    MSID_LOG_INFO_PII(params,
                 @"-[MSALPublicClientApplication acquireTokenSilentForScopes:%@\n"
                  "                                                  account:%@\n"
                  "                                             forceRefresh:%@\n"
                  "                                            correlationId:%@\n]",
                 scopes, account, forceRefresh ? @"Yes" : @"No", correlationId);
    
    MSALCompletionBlock block = ^(MSALResult *result, NSError *error)
    {
        [MSALPublicClientApplication logOperation:@"acquireTokenSilent" result:result error:error context:params];
        completionBlock(result, error);
    };

    params.unvalidatedAuthority = msidAuthority;
    params.redirectUri = _redirectUri;
    params.clientId = _clientId;
    params.urlSession = [MSALURLSession createMSALSession:params];

    NSError *error = nil;
    MSALSilentRequest *request = [[MSALSilentRequest alloc] initWithParameters:params
                                                                  forceRefresh:forceRefresh
                                                                    tokenCache:self.tokenCache
                                                                         error:&error];
    
    if (!request)
    {
        [params.urlSession invalidateAndCancel];
        block(nil, error);
        return;
    }
    
    [request run:^(MSALResult *result, NSError *error) {
        [params.urlSession invalidateAndCancel];
        block(result, error);
    }];
}

#pragma mark -
#pragma mark remove account from cache

- (BOOL)removeAccount:(MSALAccount *)account
                error:(NSError * __autoreleasing *)error
{
    if (!account)
    {
        return YES;
    }

    NSError *msidError = nil;
    __auto_type host = self.authority.msidAuthority.environment;
    BOOL result = [self.tokenCache clearCacheForAccount:account.lookupAccountIdentifier
                                            environment:host
                                               clientId:self.clientId
                                                context:nil
                                                  error:&msidError];

    if (msidError && error)
    {
        *error = msidError;
    }

    return result;
}

@end


@implementation MSALPublicClientApplication (Internal)

+ (NSDictionary *)defaultSliceParameters
{
    return @{ DEFAULT_SLICE_PARAMS };
}

@end
