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

#import <Foundation/Foundation.h>

@class MSALAccountId;
@class MSALTenantProfile;
@class MSALPublicClientApplication;

@interface MSALAccount : NSObject <NSCopying>

/*!
 Shorthand name by which the End-User wishes to be referred to at the RP, such as janedoe or j.doe. This value MAY be any valid JSON string including special characters such as @, /, or whitespace.
 Mostly maps to UserPrincipleName(UPN) in case of AAD.
 Can be nil if not returned from the service.
 */
@property (readonly, nullable) NSString *username;

/*!
 Unique identifier for the account.
 Save this for account lookups from cache at a later point.
 */
@property (readonly, nullable) NSString *identifier;

/*!
 Unique identifier of the account in the home tenant.
 This can be used later to retrieve accounts and tokens silently from MSAL.
 */
@property (readonly, nullable) MSALAccountId *homeAccountId DEPRECATED_MSG_ATTRIBUTE("Use MSALAccount.identifier property instead");

/*!
 Host part of the authority string used for authentication based on the issuer identifier.
 Note that if a host supports multiple tenants, there'll be one MSALAccount for the host and one tenant profile per each tenant accessed.
 If a host doesn't support multiple tenants, there'll be one MSALAccount with one tenant profile per host returned.
 
 e.g. if app accesses following tenants: Contoso.com and MyOrg.com in the Public AAD cloud, there'll be following information returned:
 
MSALAccount
- environment of "login.microsoftonline.com"
- identifier based on the GUID of "MyOrg.com"
- accountClaims for the "MyOrg.com"
- tenantProfiles
    - tenantProfile[0]
        - identifier based on account identifiers from "MyOrg.com" (account object id in MyOrg.com and tenant Id for MyOrg.com directory)
        - claims for the id token issued by MyOrg.com
    - tenantProfile[1]
        - identifier based on account identifiers from "Contoso.com"
        - claims for the id token issued by Contoso.com
 */
@property (readonly, nonnull) NSString *environment;

/*!
 ID token claims for the account.
 Can be used to read additional information about the account, e.g. name
 Will only be returned if there has been an id token issued for the client Id for the account's source tenant.
*/
@property (readonly, nullable) NSDictionary<NSString *, NSString *> *accountClaims;

@end

