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
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ADResponseCacheHandler.h"
#import "ADAuthenticationResult+Internal.h"
#import "MSIDLegacySingleResourceToken.h"
#import "ADTokenCacheItem+MSIDTokens.h"
#import "ADAuthenticationContext+Internal.h"
#import "MSIDSharedTokenCache.h"
#import "MSIDError.h"
#import "MSIDAADV1Oauth2Strategy.h"

@implementation ADResponseCacheHandler

+ (ADAuthenticationResult *)processAndCacheResponse:(MSIDTokenResponse *)response
                                   fromRefreshToken:(MSIDBaseToken<MSIDRefreshableToken> *)refreshToken
                                              cache:(MSIDSharedTokenCache *)cache
                                             params:(ADRequestParameters *)requestParams
{
    NSError *msidError = nil;

    MSIDAADV1Oauth2Strategy *strategy = [MSIDAADV1Oauth2Strategy new];
    
    BOOL result = [strategy verifyResponse:response
                          fromRefreshToken:refreshToken != nil
                                   context:requestParams
                                     error:&msidError];
    
    if (!result)
    {
        if (response.oauthErrorCode == MSIDErrorInvalidGrant && refreshToken)
        {
            NSError *removeError = nil;
            
            BOOL result = [cache removeRTForAccount:requestParams.account
                                              token:refreshToken
                                            context:requestParams
                                              error:&removeError];
            
            if (!result)
            {
                MSID_LOG_WARN(requestParams, @"Failed removing refresh token");
                MSID_LOG_WARN_PII(requestParams, @"Failed removing refresh token for account %@, token %@", requestParams.account, refreshToken);
            }
        }
        
        return [ADAuthenticationResult resultFromMSIDError:msidError correlationId:requestParams.correlationId];
    }
    
    result = [cache saveTokensWithStrategy:strategy
                             requestParams:requestParams.msidParameters
                                  response:response
                                   context:requestParams
                                     error:&msidError];
    
    if (!result)
    {
        return [ADAuthenticationResult resultFromMSIDError:msidError correlationId:requestParams.correlationId];
    }
    
    MSIDLegacySingleResourceToken *resultToken = [strategy legacyTokenFromResponse:response request:requestParams.msidParameters];
    
    ADTokenCacheItem *adTokenCacheItem = [[ADTokenCacheItem alloc] initWithLegacySingleResourceToken:resultToken];
    
    ADAuthenticationResult *adResult = [ADAuthenticationResult resultFromTokenCacheItem:adTokenCacheItem
                                                              multiResourceRefreshToken:response.isMultiResource
                                                                          correlationId:requestParams.correlationId];
    
    return [ADAuthenticationContext updateResult:adResult toUser:[requestParams identifier]]; //Verify the user
}

@end
