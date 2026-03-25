## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Objective-C — Language Reference

Loaded by `coder/SKILL.md` when the project is Objective-C (iOS, macOS, or mixed ObjC/Swift).

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Classes | UpperCamelCase + 2-3 letter prefix | `SSDSubscriptionService`, `SSDUserModel` |
| Methods | lowerCamelCase, verbose descriptors | `createSubscriptionForUser:withPlan:completion:` |
| Properties | lowerCamelCase | `isActive`, `expirationDate` |
| Constants | `k` prefix + UpperCamelCase | `kSSDMaxRetryCount` |
| Macros | SCREAMING_SNAKE_CASE | `SSD_ASSERT_MAIN_THREAD` |
| Protocols | Noun or -Delegate / -DataSource suffix | `SSDSubscriptionDelegate`, `SSDUserProviding` |
| Enums | TypeName + CaseName | `SSDSubscriptionStatusActive` |

**Always use a 2–3 letter class prefix.** Objective-C has no namespaces; prefixes prevent symbol collisions, especially when shipping libraries or mixing with third-party code.

---

## File Organization

```
SSDSubscriptionService.h    # interface + public API
SSDSubscriptionService.m    # implementation
SSDSubscriptionService+Private.h  # private category (optional)
```

```objc
// SSDSubscriptionService.h
#import <Foundation/Foundation.h>
#import "SSDSubscription.h"
#import "SSDSubscriptionServiceDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// Manages subscription lifecycle operations.
@interface SSDSubscriptionService : NSObject

@property (nonatomic, weak, nullable) id<SSDSubscriptionServiceDelegate> delegate;

/// Designated initializer.
- (instancetype)initWithRepository:(id<SSDSubscriptionRepository>)repository
                    paymentGateway:(id<SSDPaymentGateway>)gateway NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Creates a new subscription. Calls delegate on completion.
- (void)createSubscriptionForUserID:(NSUUID *)userID
                             planID:(NSUUID *)planID
                         completion:(void (^)(SSDSubscription * _Nullable subscription,
                                              NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
```

```objc
// SSDSubscriptionService.m
#import "SSDSubscriptionService.h"
#import "SSDSubscription+Private.h"
#import "SSDErrors.h"

@interface SSDSubscriptionService ()
@property (nonatomic, strong) id<SSDSubscriptionRepository> repository;
@property (nonatomic, strong) id<SSDPaymentGateway> paymentGateway;
@end

@implementation SSDSubscriptionService

- (instancetype)initWithRepository:(id<SSDSubscriptionRepository>)repository
                    paymentGateway:(id<SSDPaymentGateway>)gateway {
    self = [super init];
    if (self) {
        _repository     = repository;
        _paymentGateway = gateway;
    }
    return self;
}

// ...

@end
```

---

## Properties

Declare properties with explicit memory management and thread semantics:

```objc
// Immutable value types
@property (nonatomic, copy)     NSString   *userName;
@property (nonatomic, copy)     NSDate     *expirationDate;

// Object references
@property (nonatomic, strong)   SSDSubscription *subscription;

// Delegates — always weak to avoid retain cycles
@property (nonatomic, weak)     id<SSDSubscriptionDelegate> delegate;

// Primitives
@property (nonatomic, assign)   BOOL       isActive;
@property (nonatomic, assign)   NSInteger  retryCount;

// Read-only externally, read-write internally (redeclare in .m)
@property (nonatomic, readonly) NSUUID *subscriptionID;
```

**Rules:**
- `copy` for `NSString`, `NSArray`, `NSDictionary`, `NSSet` (prevents mutation from outside)
- `strong` for owned objects
- `weak` for delegates and parent references (break retain cycles)
- `assign` for primitives and `__unsafe_unretained` for C types

---

## Nullability Annotations

Always annotate nullability in public headers. Use `NS_ASSUME_NONNULL_BEGIN/END` to set a non-null default:

```objc
NS_ASSUME_NONNULL_BEGIN

@interface SSDSubscriptionService : NSObject

// Return is nullable (subscription may not exist)
- (nullable SSDSubscription *)subscriptionForID:(NSUUID *)subscriptionID;

// Parameter is nullable (reason is optional)
- (void)cancelSubscription:(SSDSubscription *)subscription
                    reason:(nullable NSString *)reason
                completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
```

---

## Error Handling (NSError**)

Objective-C uses the `NSError**` out-parameter pattern for synchronous errors, and `NSError*` in completion blocks for async errors:

```objc
// Define error domain and codes in a dedicated header
extern NSErrorDomain const SSDSubscriptionErrorDomain;

typedef NS_ENUM(NSInteger, SSDSubscriptionErrorCode) {
    SSDSubscriptionErrorAlreadyActive  = 1001,
    SSDSubscriptionErrorPlanNotFound   = 1002,
    SSDSubscriptionErrorPaymentFailed  = 1003,
};

// Helper to create errors
static inline NSError *SSDSubscriptionError(SSDSubscriptionErrorCode code, NSString *description) {
    return [NSError errorWithDomain:SSDSubscriptionErrorDomain
                              code:code
                          userInfo:@{NSLocalizedDescriptionKey: description}];
}
```

```objc
// Synchronous — NSError** out-param
- (nullable SSDSubscription *)cancelSubscription:(SSDSubscription *)subscription
                                           error:(NSError **)error {
    if (!subscription.isActive) {
        if (error) {
            *error = SSDSubscriptionError(
                SSDSubscriptionErrorAlreadyActive,
                @"Subscription is not active and cannot be cancelled."
            );
        }
        return nil;
    }
    // ... perform cancellation
    return subscription;
}

// Async — error in completion block
- (void)createSubscriptionForUserID:(NSUUID *)userID
                             planID:(NSUUID *)planID
                         completion:(void (^)(SSDSubscription * _Nullable, NSError * _Nullable))completion {
    [self.repository findUserByID:userID completion:^(SSDUser * _Nullable user, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (user.hasActiveSubscription) {
            completion(nil, SSDSubscriptionError(
                SSDSubscriptionErrorAlreadyActive,
                @"User already has an active subscription."
            ));
            return;
        }
        // ... continue
    }];
}
```

**Always check `if (error)` before writing to `*error`** — the caller may pass `NULL`.

---

## Delegate Pattern

```objc
// Protocol definition
@protocol SSDSubscriptionServiceDelegate <NSObject>
@optional
- (void)subscriptionService:(SSDSubscriptionService *)service
    didCreateSubscription:(SSDSubscription *)subscription;
- (void)subscriptionService:(SSDSubscriptionService *)service
    didFailWithError:(NSError *)error;
@end

// Calling delegate methods safely
- (void)notifyDelegateOfSubscription:(SSDSubscription *)subscription {
    if ([self.delegate respondsToSelector:@selector(subscriptionService:didCreateSubscription:)]) {
        [self.delegate subscriptionService:self didCreateSubscription:subscription];
    }
}
```

---

## Categories and Extensions

Use categories for logical groupings and to extend existing classes:

```objc
// SSDSubscription+Validation.h
@interface SSDSubscription (Validation)
- (BOOL)isValidForDate:(NSDate *)date;
- (BOOL)canBeRenewed;
@end

// SSDSubscription+Validation.m
@implementation SSDSubscription (Validation)
- (BOOL)isValidForDate:(NSDate *)date {
    return self.isActive && [self.expirationDate compare:date] == NSOrderedDescending;
}
@end
```

Use class extensions (anonymous categories in `.m`) for private declarations:

```objc
// In SSDSubscriptionService.m — private interface
@interface SSDSubscriptionService ()
@property (nonatomic, strong) id<SSDSubscriptionRepository> repository;
- (void)processPaymentForUser:(SSDUser *)user amount:(NSDecimalNumber *)amount
                   completion:(void (^)(SSDPayment *, NSError *))completion;
@end
```

---

## Threading

Always update UI on the main thread. Use GCD for async work:

```objc
// ❌ Updating UI from background thread
[self.repository fetchSubscriptions:^(NSArray *subs, NSError *error) {
    self.subscriptions = subs;                      // might be on background thread
    [self.tableView reloadData];                    // crash: UI update off main thread
}];

// ✅ Dispatch back to main thread
[self.repository fetchSubscriptions:^(NSArray *subs, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.subscriptions = subs;
        [self.tableView reloadData];
    });
}];

// ✅ For serial background work
dispatch_queue_t queue = dispatch_queue_create("com.ssd.subscription", DISPATCH_QUEUE_SERIAL);
dispatch_async(queue, ^{
    // background work
    dispatch_async(dispatch_get_main_queue(), ^{
        // UI update
    });
});
```

---

## Modern Objective-C Literals and Syntax

Use modern literals — they are shorter and safer:

```objc
// ❌ Old style
NSArray  *arr  = [NSArray arrayWithObjects:@"a", @"b", nil];
NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"key", nil];
NSNumber *n    = [NSNumber numberWithInt:42];

// ✅ Modern literals
NSArray      *arr = @[@"a", @"b"];
NSDictionary *d   = @{@"key": @"value"};
NSNumber     *n   = @42;
BOOL          b   = YES;

// ✅ Subscript access
NSString *val = d[@"key"];
NSString *item = arr[0];
```

---

## Testing (XCTest)

```objc
#import <XCTest/XCTest.h>
#import "SSDSubscriptionService.h"
#import "SSDMockSubscriptionRepository.h"

@interface SSDSubscriptionServiceTests : XCTestCase
@property (nonatomic, strong) SSDSubscriptionService *service;
@property (nonatomic, strong) SSDMockSubscriptionRepository *mockRepo;
@end

@implementation SSDSubscriptionServiceTests

- (void)setUp {
    [super setUp];
    self.mockRepo = [[SSDMockSubscriptionRepository alloc] init];
    self.service  = [[SSDSubscriptionService alloc] initWithRepository:self.mockRepo
                                                        paymentGateway:[[SSDMockPaymentGateway alloc] init]];
}

- (void)testCreateSubscriptionCallsCompletion {
    XCTestExpectation *exp = [self expectationWithDescription:@"completion called"];

    [self.service createSubscriptionForUserID:[NSUUID UUID]
                                       planID:[NSUUID UUID]
                                   completion:^(SSDSubscription *sub, NSError *error) {
        XCTAssertNotNil(sub);
        XCTAssertNil(error);
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
```

---

## Objective-C-Specific Quality Checklist

- [ ] All classes have a 2–3 letter prefix
- [ ] All public headers wrapped in `NS_ASSUME_NONNULL_BEGIN/END`
- [ ] `copy` used for `NSString`, `NSArray`, `NSDictionary` properties
- [ ] `weak` used for delegate properties — no retain cycles
- [ ] All `NSError**` out-params guarded with `if (error)` before write
- [ ] UI updates dispatched to `dispatch_get_main_queue()`
- [ ] Protocols define `@required` / `@optional` sections explicitly
- [ ] No `performSelector:` without suppressing the `-Warc-performSelector-leaks` warning with documentation

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| EXC_BAD_ACCESS crash | Over-released object or dangling pointer | Enable zombies (`NSZombieEnabled`); check ARC ownership |
| Retain cycle / memory leak | `strong` delegate or `self` captured strongly in block | Use `weak` delegate; `__weak typeof(self) weakSelf = self` in blocks |
| UI not updating | Callback on background thread | Dispatch UI work to `dispatch_get_main_queue()` |
| Silent error loss | `NSError**` written without checking `if (error)` | Always guard `if (error) { *error = ...; }` |
| NSString mutation surprise | Property declared `strong` instead of `copy` | Use `copy` for all value-type collection/string properties |
| Selector not found crash | `respondsToSelector:` not checked for `@optional` | Always check before calling optional delegate methods |
| Category method collision | Two categories define same method on same class | Prefix category methods: `ssd_methodName` |
