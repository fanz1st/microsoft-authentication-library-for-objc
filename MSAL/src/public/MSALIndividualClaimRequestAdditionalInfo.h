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
#import "MSALJsonSerializable.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 Represents the additional information that can be sent to an authorization server for a request claim in the claim request parameter.
 See more info here: https://openid.net/specs/openid-connect-core-1_0.html#IndividualClaimsRequests
 */
@interface MSALIndividualClaimRequestAdditionalInfo : NSObject

/*!
 Indicates whether the Claim being requested is an Essential Claim.
*/
@property (nonatomic, nullable) NSNumber *essential;

/*!
 Requests that the Claim be returned with a particular value.
 */
@property (nonatomic, nullable) id value;

/*
 Requests that the Claim be returned with one of a set of values, with the values appearing in order of preference.
 */
@property (nonatomic, nullable) NSSet *values;

@end

NS_ASSUME_NONNULL_END
