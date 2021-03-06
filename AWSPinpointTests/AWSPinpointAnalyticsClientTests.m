//
// Copyright 2010-2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.
// A copy of the License is located at
//
// http://aws.amazon.com/apache2.0
//
// or in the "license" file accompanying this file. This file is distributed
// on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
// express or implied. See the License for the specific language governing
// permissions and limitations under the License.
//

#import <XCTest/XCTest.h>
#import "AWSTestUtility.h"
#import "AWSPinpoint.h"
#import "OCMock.h"

NSString *const AWSPinpointAnalyticsClientErrorDomain = @"com.amazonaws.AWSPinpointAnalyticsClientErrorDomain";

@interface AWSPinpointAnalyticsClientTests : XCTestCase
@property (nonatomic, strong) AWSPinpoint *pinpoint;

@end

@implementation AWSPinpointAnalyticsClientTests

- (void)setUp {
    [super setUp];
    [[AWSLogger defaultLogger] setLogLevel:AWSLogLevelVerbose];

    [AWSTestUtility setupCognitoCredentialsProvider];
    
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"credentials"
                                                                          ofType:@"json"];
    NSDictionary *credentialsJson = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:filePath]
                                                                    options:NSJSONReadingMutableContainers
                                                                      error:nil];
    AWSPinpointConfiguration *configuration = [[AWSPinpointConfiguration alloc] initWithAppId:credentialsJson[@"pinpointAppId"] launchOptions:@{}];

    self.pinpoint = [AWSPinpoint pinpointWithConfiguration:configuration];
    [self.pinpoint.analyticsClient.eventRecorder removeAllEvents];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testConstructors {
    @try {
        AWSPinpointAnalyticsClient *analyticsClient = [AWSPinpointAnalyticsClient new];
        XCTFail(@"Expected an exception to be thrown. %@", analyticsClient);
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, NSInternalInconsistencyException);
    }
}

- (void) testCreateEvent {
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    XCTAssertTrue([[event eventType] isEqualToString:@"TEST_EVENT"]);
    XCTAssertTrue([event hasMetricForKey:@"Mettr1"]);
    XCTAssertTrue([event hasAttributeForKey:@"Attr1"]);
    XCTAssertTrue([[event attributeForKey:@"Attr1"] isEqualToString:@"Attr1"]);
    XCTAssertTrue([[event metricForKey:@"Mettr1"] isEqualToNumber:@(1)]);
}

- (void) testCreateAppleMonetizationEvent {
    SKPaymentTransaction *transaction = OCMClassMock([SKPaymentTransaction class]);
    SKProduct *product = OCMClassMock([SKProduct class]);

    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createAppleMonetizationEventWithTransaction:transaction
                                                                                             withProduct:product];
    XCTAssertNotNil(event);
    XCTAssertTrue([[event eventType] isEqualToString:@"_monetization.purchase"]);
    XCTAssertTrue([event hasAttributeForKey:@"_store"]);
    XCTAssertTrue([event hasAttributeForKey:@"_item_price_formatted"]);
    XCTAssertTrue([event hasMetricForKey:@"_quantity"]);
    XCTAssertTrue([event hasMetricForKey:@"_item_price"]);
    XCTAssertTrue([[event attributeForKey:@"_store"] isEqualToString:@"Apple"]);
    XCTAssertTrue([[event attributeForKey:@"_item_price_formatted"] isEqualToString:@"$0.00"]);
    XCTAssertTrue([[event metricForKey:@"_quantity"] isEqualToNumber:@(0)]);
    XCTAssertTrue([[event metricForKey:@"_item_price"] isEqualToNumber:@(0)]);
}

- (void) testCreateVirtualMonetizationEvent {
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createVirtualMonetizationEventWithProductId:@"PRODUCT_ID"
                                                                                           withItemPrice:123.99
                                                                                            withQuantity:123
                                                                                            withCurrency:@"CURRENCY"];
    XCTAssertNotNil(event);
    XCTAssertTrue([[event eventType] isEqualToString:@"_monetization.purchase"]);
    XCTAssertTrue([event hasAttributeForKey:@"_store"]);
    XCTAssertTrue([event hasMetricForKey:@"_quantity"]);
    XCTAssertTrue([event hasMetricForKey:@"_item_price"]);
    XCTAssertTrue([[event attributeForKey:@"_store"] isEqualToString:@"Virtual"]);
    XCTAssertTrue([[event metricForKey:@"_quantity"] isEqualToNumber:@(123)]);
    XCTAssertTrue([[event metricForKey:@"_item_price"] isEqualToNumber:@(123.99)]);
}

- (void) testRecordEvent {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Test finished running."];

    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];

    XCTAssertNotNil(event);
    XCTAssertTrue([[event eventType] isEqualToString:@"TEST_EVENT"]);
    XCTAssertTrue([event hasMetricForKey:@"Mettr1"]);
    XCTAssertTrue([event hasAttributeForKey:@"Attr1"]);
    XCTAssertTrue([[event attributeForKey:@"Attr1"] isEqualToString:@"Attr1"]);
    XCTAssertTrue([[event metricForKey:@"Mettr1"] isEqualToNumber:@(1)]);
    
    [[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }];
    
    [[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        XCTAssertNotNil(task.result);
        
        XCTAssertEqual([task.result count], 1);
        
        //Extract Event and compare event type and timestamp
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        
        [expectation fulfill];
        return nil;
    }];
    
    [self waitForExpectationsWithTimeout:5 handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];
}

- (void) testRetrieveRecordedEvents {
    
    [[[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNotNil(task.result);
        //Should be empty
        XCTAssertEqual([task.result count], 0);
        return nil;
    }] waitUntilFinished];
    
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    [[[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }] waitUntilFinished];
    
    [[[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNotNil(task.result);
        //Should be empty
        XCTAssertEqual([task.result count], 1);
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        
        return nil;
    }] waitUntilFinished];
}

- (void) testSubmitEvents {
    [[AWSLogger defaultLogger] setLogLevel:AWSLogLevelVerbose];

    [[[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNotNil(task.result);
        //Should be empty
        XCTAssertEqual([task.result count], 0);
        return nil;
    }] waitUntilFinished];
    
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    [[[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }] waitUntilFinished];
    
    [[[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNotNil(task.result);
        //Should be empty
        XCTAssertEqual([task.result count], 1);
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        
        return nil;
    }] waitUntilFinished];
    
    [[[self.pinpoint.analyticsClient submitEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        XCTAssertNotNil(task.result);
        
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        return nil;
    }] waitUntilFinished];
    
    [[[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNotNil(task.result);
        //Should be empty
        XCTAssertEqual([task.result count], 0);
        return nil;
    }] waitUntilFinished];
}

- (void) testGlobalAttribute {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Test finished running."];
    
    [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:@"GlobalAttr1"];
    
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    [[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }];
    
    [[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        XCTAssertNotNil(task.result);
        
        XCTAssertEqual([task.result count], 1);
        
        //Extract Event and compare event type and timestamp
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"GlobalAttr1"] isEqualToString:@"GlobalAttr1"]);

        [expectation fulfill];
        return nil;
    }];
    
    [self waitForExpectationsWithTimeout:5 handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];
}

- (void) testGlobalAttributeValidation {
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:@"GlobalAttr1"];
#pragma clang diagnostic pop

        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }

    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"TestKeyLength0" forKey:@""];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
}

- (void) testGlobalAttributeForEventTypeValidation {
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:@"GlobalAttr1" forEventType:@"GlobalAttr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:nil forEventType:@"GlobalAttr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:@"GlobalAttr1" forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:nil forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:nil forEventType:@"GlobalAttr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:nil forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:nil forKey:@"GlobalAttr1" forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalAttribute:@"TestKeyLength0" forKey:@"" forEventType:@"TestKeyLength0"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }

}

- (void) testGlobalMetric {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Test finished running."];
    
    [self.pinpoint.analyticsClient addGlobalMetric:@(11) forKey:@"GlobalMetr1"];
    
    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    [[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }];
    
    [[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        XCTAssertNotNil(task.result);
        
        XCTAssertEqual([task.result count], 1);
        
        //Extract Event and compare event type and timestamp
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"GlobalMetr1"] intValue], @(11).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        
        [expectation fulfill];
        return nil;
    }];
    
    [self waitForExpectationsWithTimeout:5 handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];
}


- (void) testGlobalMetricValidation {
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:@"GlobalMetr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:@""];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
}

- (void) testGlobalMetricForEventTypeValidation {
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:@"GlobalMetr1" forEventType:@"GlobalMetr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:nil forEventType:@"GlobalMetr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:@"GlobalMetr1" forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:nil forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:nil forEventType:@"GlobalMetr1"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:nil forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:nil forKey:@"GlobalMetr1" forEventType:nil];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [self.pinpoint.analyticsClient addGlobalMetric:@(1) forKey:@"" forEventType:@"TestKeyLength0"];
#pragma clang diagnostic pop
        
        XCTFail(@"Expected an exception to be thrown. Insert nil parameter");
    }
    @catch (NSException *exception) {
        XCTAssertEqualObjects(exception.name, AWSPinpointAnalyticsClientErrorDomain);
    }
    
}

- (void) testGlobalAttributeAndMetric {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Test finished running."];
    
    [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr1" forKey:@"GlobalAttr1"];
    [self.pinpoint.analyticsClient addGlobalAttribute:@"GlobalAttr2" forKey:@"GlobalAttr2"];

    [self.pinpoint.analyticsClient addGlobalMetric:@(123) forKey:@"GlobalMetr1"];
    [self.pinpoint.analyticsClient addGlobalMetric:@(321) forKey:@"GlobalMetr2"];

    AWSPinpointEvent *event = [self.pinpoint.analyticsClient createEventWithEventType:@"TEST_EVENT"];
    [event addAttribute:@"Attr1" forKey:@"Attr1"];
    [event addMetric:@(1) forKey:@"Mettr1"];
    
    XCTAssertNotNil(event);
    [[self.pinpoint.analyticsClient recordEvent:event] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        return nil;
    }];
    
    [[self.pinpoint.analyticsClient.eventRecorder getEvents] continueWithBlock:^id _Nullable(AWSTask * _Nonnull task) {
        XCTAssertNil(task.error);
        XCTAssertNotNil(task.result);
        
        XCTAssertEqual([task.result count], 1);
        
        //Extract Event and compare event type and timestamp
        AWSPinpointEvent *resultEvent = [task.result firstObject];
        XCTAssertNotNil(resultEvent);
        XCTAssertTrue([resultEvent.eventType isEqualToString:event.eventType]);
        XCTAssertEqual(resultEvent.eventTimestamp, event.eventTimestamp);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"Mettr1"] intValue], @(1).intValue);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"GlobalMetr1"] intValue], @(123).intValue);
        XCTAssertEqual([[resultEvent.allMetrics objectForKey:@"GlobalMetr2"] intValue], @(321).intValue);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"Attr1"] isEqualToString:@"Attr1"]);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"GlobalAttr1"] isEqualToString:@"GlobalAttr1"]);
        XCTAssertTrue([[resultEvent.allAttributes objectForKey:@"GlobalAttr2"] isEqualToString:@"GlobalAttr2"]);
        
        [expectation fulfill];
        return nil;
    }];
    
    [self waitForExpectationsWithTimeout:5 handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

}

@end
