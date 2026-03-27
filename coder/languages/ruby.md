## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Ruby — Language Reference

Loaded by `coder/SKILL.md` when the project is Ruby.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Methods | snake_case, verb phrase | `cancel_subscription`, `find_by_email` |
| Classes | CamelCase, noun phrase | `SubscriptionService`, `PaymentProcessor` |
| Modules | CamelCase | `Billable`, `Authenticatable` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_CURRENCY` |
| Files | snake_case | `subscription_service.rb`, `payment_gateway.rb` |
| Booleans | ? suffix | `active?`, `has_subscription?`, `can_cancel?` |
| Bang methods | ! suffix (dangerous/mutating) | `cancel!`, `normalize_email!` |
| Private | No prefix — use `private` keyword | `validate_payment_method` |

---

## File Organization

```ruby
# frozen_string_literal: true

# Standard library
require "net/http"
require "json"
require "securerandom"

# Third-party gems
require "stripe"
require "sidekiq"

# Local
require_relative "concerns/billable"
require_relative "payment_gateway"

module Subscriptions
  # Constants
  MAX_RENEWAL_ATTEMPTS = 3
  GRACE_PERIOD_DAYS = 7

  class Service
    include Billable

    # Class methods, initializer, public methods, then private.
    # ...
  end
end
```

Always add `# frozen_string_literal: true` as the first line. It prevents accidental
string mutation and improves performance. RuboCop enforces this.

---

## Blocks, Procs, and Lambdas

Use **blocks** for iteration and DSLs. Use **lambdas** when you need a reusable
callable with strict arity. Use **Procs** almost never — lambdas are safer.

```ruby
# Block — the default. Use for iteration, callbacks, DSLs.
active_subscriptions = subscriptions.select { |sub| sub.active? }

# Multi-line blocks use do...end.
subscriptions.each do |subscription|
  SubscriptionMailer.renewal_reminder(subscription).deliver_later
end

# Lambda — a reusable callable with strict argument checking.
discount_calculator = ->(plan, coupon) {
  return plan.price if coupon.nil?
  plan.price * (1 - coupon.discount_rate)
}
final_price = discount_calculator.call(plan, coupon)

# Lambda as strategy pattern.
CHARGE_STRATEGIES = {
  stripe:  ->(amount, token) { StripeGateway.charge(amount, token) },
  paypal:  ->(amount, token) { PaypalGateway.charge(amount, token) },
}.freeze

def process_payment(gateway, amount, token)
  strategy = CHARGE_STRATEGIES.fetch(gateway)
  strategy.call(amount, token)
end
```

**Rule of thumb:** if it's inline and single-use, it's a block. If you're storing
it in a variable or a hash, it's a lambda. If you think you need a Proc, you don't.

---

## Duck Typing and Mixins

Prefer modules over inheritance. Ruby's power is composition, not deep class trees.

```ruby
# Good — a mixin that any model can include.
module Billable
  def charge(amount, payment_method_id:)
    PaymentGateway.charge(
      customer_id: billing_customer_id,
      amount: amount,
      payment_method_id: payment_method_id
    )
  end

  def billing_customer_id
    raise NotImplementedError, "#{self.class} must implement #billing_customer_id"
  end
end

class User
  include Billable

  def billing_customer_id
    stripe_customer_id
  end
end

class Organization
  include Billable

  def billing_customer_id
    corporate_billing_id
  end
end
```

Use `respond_to?` for duck typing instead of `is_a?`:

```ruby
# Bad — couples to a specific class.
def notify(recipient)
  raise ArgumentError unless recipient.is_a?(User)
  recipient.send_email(message)
end

# Good — duck typing. Anything that responds to the method works.
def notify(recipient)
  unless recipient.respond_to?(:send_email)
    raise ArgumentError, "recipient must respond to #send_email"
  end
  recipient.send_email(message)
end
```

---

## Error Handling

Define a hierarchy of specific exceptions per domain:

```ruby
# errors.rb
module Subscriptions
  class Error < StandardError; end
  class NotFoundError < Error; end
  class ExpiredError < Error; end
  class AlreadyActiveError < Error; end

  class PaymentFailedError < Error
    attr_reader :gateway_code

    def initialize(message, gateway_code: nil)
      @gateway_code = gateway_code
      super(message)
    end
  end
end
```

Rescue at boundaries. Let domain exceptions propagate up to controllers:

```ruby
class SubscriptionsController < ApplicationController
  def create
    subscription = Subscriptions::Service.new(current_user)
      .create(plan: plan, payment_method_id: params[:payment_method_id])
    render json: { subscription_id: subscription.id }, status: :created
  rescue Subscriptions::AlreadyActiveError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Subscriptions::PaymentFailedError => e
    Rails.logger.warn("Payment failed: #{e.message}", gateway_code: e.gateway_code)
    render json: { error: "Payment could not be processed" }, status: :payment_required
  rescue Subscriptions::Error => e
    render json: { error: e.message }, status: :bad_request
  end
end
```

Never rescue `Exception` — that catches `SignalException` and `SystemExit`. Rescue
`StandardError` (the default) or your own domain errors.

---

## Testing (RSpec)

RSpec is the standard. Use `describe` for the unit, `context` for state, `it` for behavior.

```ruby
# spec/services/subscriptions/service_spec.rb
RSpec.describe Subscriptions::Service do
  subject(:service) { described_class.new(user) }

  let(:user) { create(:user) }
  let(:plan) { create(:plan, price_cents: 999) }
  let(:payment_method_id) { "pm_test_#{SecureRandom.hex(4)}" }

  describe "#create" do
    context "when user has no active subscription" do
      it "creates an active subscription" do
        subscription = service.create(plan: plan, payment_method_id: payment_method_id)

        expect(subscription).to be_active
        expect(subscription.user).to eq(user)
        expect(subscription.plan).to eq(plan)
      end

      it "charges the user" do
        expect(PaymentGateway).to receive(:charge).with(
          customer_id: user.stripe_customer_id,
          amount: 999,
          payment_method_id: payment_method_id
        )

        service.create(plan: plan, payment_method_id: payment_method_id)
      end
    end

    context "when user already has an active subscription" do
      before { create(:subscription, user: user, status: :active) }

      it "raises AlreadyActiveError" do
        expect {
          service.create(plan: plan, payment_method_id: payment_method_id)
        }.to raise_error(Subscriptions::AlreadyActiveError, /already has an active/)
      end
    end
  end
end
```

Use **FactoryBot** for test data, not fixtures. Use `let` (lazy) over instance
variables. Use `subject` for the object under test. Prefer `expect` syntax — never
`should`.

Minitest ships with Ruby and works fine for libraries. For applications, RSpec's
expressiveness wins.

---

## Ruby-Specific Quality Checklist

- [ ] `# frozen_string_literal: true` on every file
- [ ] RuboCop passes with zero offenses
- [ ] No monkey-patching of core classes (`String`, `Array`, `Hash`)
- [ ] No `rescue Exception` — rescue `StandardError` or narrower
- [ ] Service objects for business logic — not in models or controllers
- [ ] Mutable state avoided — prefer `freeze`, `map`, and functional transforms
- [ ] No `method_missing` without a matching `respond_to_missing?`
- [ ] Bang methods (`!`) reserved for dangerous or mutating operations only
- [ ] Enumerable methods (`map`, `select`, `reject`) over manual loops

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `FrozenError: can't modify frozen String` | Missing `dup` on a frozen string literal | Use `String.new` or `.dup` when mutation is intentional |
| N+1 queries | Missing eager loading | Add `includes(:association)` to the query |
| `NoMethodError` on nil | Unexpected nil in a chain | Use safe navigation (`&.`) or guard with early return |
| Thread-unsafe code | Mutable class-level state | Use `freeze`, `Concurrent::Map`, or request-local storage |
| Slow test suite | Excessive database hits | Use `build_stubbed` instead of `create` where possible |
| `method_missing` black hole | No `respond_to_missing?` defined | Always define `respond_to_missing?` alongside `method_missing` |
| Silent type coercion bugs | Implicit `to_s` / `to_i` on nil | Validate inputs at boundaries; `nil.to_i` is `0`, not an error |
| Gem version conflicts | Loose version constraints in Gemfile | Pin major versions with pessimistic operator (`~> 3.0`) |
