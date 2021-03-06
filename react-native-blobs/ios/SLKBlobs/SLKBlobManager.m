/**
 * Copyright (c) 2015-2016 Silk Labs, Inc.
 * All Rights Reserved.
 */

#import "SLKBlobManager.h"
#import "RCTConvert.h"

@implementation SLKBlobManager
{
  NSMutableDictionary<NSString *, NSData *> *_blobs;
  NSOperationQueue *_queue;
}

RCT_EXPORT_MODULE()

- (NSString *)store:(NSData *)data
{
  NSString *blobId = [NSUUID UUID].UUIDString;
  [self store:data withId:blobId];
  return blobId;
}

- (void)store:(NSData *)data withId:(NSString *)blobId
{
  if (!_blobs) {
    _blobs = [NSMutableDictionary new];
  }
  _blobs[blobId] = data;
}

- (NSData *)resolve:(NSDictionary<NSString *, id> *)blob
{
  NSString *blobId = [RCTConvert NSString:blob[@"blobId"]];
  NSNumber *offset = [RCTConvert NSNumber:blob[@"offset"]];
  NSNumber *size = [RCTConvert NSNumber:blob[@"size"]];
  return [self resolve:blobId
                offset:offset ? [offset integerValue] : 0
                  size:size ? [size integerValue] : -1];
}

- (NSData *)resolve:(NSString *)blobId offset:(NSInteger)offset size:(NSInteger)size
{
  NSData *data = _blobs[blobId];
  if (!data) {
    return nil;
  }
  if (offset != 0 || (size != -1 && size != data.length)) {
    data = [data subdataWithRange:NSMakeRange(offset, size)];
  }
  return data;
}

RCT_EXPORT_METHOD(createFromParts:(NSArray<NSDictionary<NSString *, id> *> *)parts withId:(NSString *)blobId)
{
  NSMutableData *data = [NSMutableData new];
  for (NSDictionary<NSString *, id> *part in parts) {
    NSData *partData = [self resolve:part];
    [data appendData:partData];
  }
  [self store:data withId:blobId];
}

RCT_EXPORT_METHOD(release:(NSString *)blobId)
{
  [_blobs removeObjectForKey:blobId];
}

#pragma mark - RCTURLRequestHandler methods

- (BOOL)canHandleRequest:(NSURLRequest *)request
{
  return [request.URL.scheme caseInsensitiveCompare:@"blob"] == NSOrderedSame;
}

- (id)sendRequest:(NSURLRequest *)request
     withDelegate:(id<RCTURLRequestDelegate>)delegate;
{
  // Lazy setup
  if (!_queue) {
    _queue = [NSOperationQueue new];
    _queue.maxConcurrentOperationCount = 2;
  }

  __weak __block NSBlockOperation *weakOp;
  __block NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:request.URL
                                                        MIMEType:nil
                                           expectedContentLength:-1
                                                textEncodingName:nil];

    [delegate URLRequest:weakOp didReceiveResponse:response];

    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:request.URL resolvingAgainstBaseURL:NO];

    NSString *blobId = components.path;
    NSInteger offset = 0;
    NSInteger size = -1;

    if (components.queryItems) {
      for (NSURLQueryItem *queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"offset"]) {
          offset = [queryItem.value integerValue];
        }
        if ([queryItem.name isEqualToString:@"size"]) {
          size = [queryItem.value integerValue];
        }
      }
    }

    NSData *data;
    if (blobId) {
      data = [self resolve:blobId offset:offset size:size];
    }
    NSError *error;
    if (data) {
      [delegate URLRequest:weakOp didReceiveData:data];
    } else {
      error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
    }
    [delegate URLRequest:weakOp didCompleteWithError:error];
  }];

  weakOp = op;
  [_queue addOperation:op];
  return op;
}

- (void)cancelRequest:(NSOperation *)op
{
  [op cancel];
}

@end


@implementation RCTBridge (SLKBlobManager)

- (SLKBlobManager *)blobs
{
  return [self moduleForClass:[SLKBlobManager class]];
}

@end
