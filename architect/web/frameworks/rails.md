## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Ruby on Rails — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Rails.

---

## When to Choose Rails

**Choose Rails when:** rapid prototyping (working product in days), MPA / server-rendered HTML (forms, redirects, flash messages — Rails wrote the playbook), content-heavy apps (CMS, marketplaces, dashboards), full-stack with Hotwire (80% of SPA UX at 20% complexity), or CRUD-dominant domains (subscription management, admin panels, e-commerce).

**Do not choose Rails when:** you need a pure API and the team knows Python/Go/TypeScript, you need sub-millisecond compute-heavy endpoints (Ruby is not fast), a standalone SPA team owns the frontend, or zero Ruby experience and no ramp-up time.

**Default posture:** if you are building a web product, your team knows Ruby, and you have no reason to avoid it — use Rails. Boring technology is a compliment.

---

## Project Structure

Follow Rails conventions. Custom directories only for services and adapters.

```
app/
├── controllers/            # Thin. Validate, call service, render.
│   ├── concerns/           # Shared behaviors (authentication, pagination)
│   └── api/v1/             # Versioned API controllers
├── models/concerns/        # Shared model behaviors (auditable, soft_deletable)
├── services/               # Business logic. One class, one public method (.call).
│   ├── subscriptions/      # create_service.rb, cancel_service.rb
│   └── payments/           # charge_service.rb
├── views/                  # ERB templates. No logic.
├── components/             # ViewComponent classes
├── jobs/                   # ActiveJob. Enqueue from services, never controllers.
└── javascript/controllers/ # Stimulus controllers
config/credentials.yml.enc  # Encrypted secrets. Never commit master.key.
db/migrate/                 # Never edit a committed migration.
lib/adapters/               # Wrappers for external APIs (Stripe, SendGrid)
spec/                       # RSpec — mirrors app/ structure (factories/, services/, requests/, system/)
```

`app/services/` exists from Day 1. `lib/adapters/` wraps every external API. No `app/lib/` or `app/utils/` junk drawers.

---

## Routing

Resourceful routing is Rails' superpower. Custom routes are a code smell — they mean resources are modeled wrong.

```ruby
Rails.application.routes.draw do
  resources :subscriptions, only: [:index, :show, :new, :create] do
    member { post :cancel; post :reactivate }
    resources :invoices, only: [:index, :show]   # One level deep only
  end
  resources :plans, only: [:index, :show]
  namespace(:api) { namespace(:v1) {
    resources :subscriptions, only: [:index, :show, :create] do member { post :cancel } end
  }}
  devise_for :users
  constraints(AdminConstraint.new) { namespace(:admin) { resources :users; resources :subscriptions } }
  root "pages#home"
end
```

**Rules:** use `resources` with `member`/`collection`, not bare `get`/`post`. Nest one level deep max. `namespace` for versioning and admin. Route constraints for authorization boundaries.

---

## Data Layer

ActiveRecord is the most productive ORM in existence — and the most dangerous if misused.

```ruby
class User < ApplicationRecord
  has_many :subscriptions, dependent: :restrict_with_error   # NOT :destroy
  has_many :active_subscriptions, -> { active }, class_name: "Subscription"
end

class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  has_many :payments, dependent: :restrict_with_error
  enum :status, { active: "active", cancelled: "cancelled", past_due: "past_due", trialing: "trialing" }
  scope :active,          -> { where(status: :active) }
  scope :expiring_within, ->(days) { active.where(current_period_end: ..days.from_now) }
  validates :status, presence: true, inclusion: { in: statuses.keys }
  validates :current_period_start, :current_period_end, presence: true

  before_validation :normalize_status          # GOOD — sets internal state only
  # after_create :send_welcome_email           # BAD — move to CreateService
  # after_save :sync_to_stripe                 # BAD — move to adapter via service
end

class Plan < ApplicationRecord
  has_many :subscriptions
  monetize :price_cents    # money-rails gem. Never store money as floats.
end
```

**Key opinions:** default to `dependent: :restrict_with_error` (cascading deletes are a production incident). Store enum values as strings, not integers. Scopes over class methods. Callbacks only set internal state — side effects belong in services.

```ruby
# Migration discipline
create_table :subscriptions do |t|
  t.references :user, null: false, foreign_key: true, index: true
  t.references :plan, null: false, foreign_key: true, index: true
  t.string     :status, null: false, default: "trialing"
  t.string     :stripe_subscription_id, index: { unique: true }
  t.datetime   :current_period_start, null: false
  t.datetime   :current_period_end, null: false
  t.datetime   :cancelled_at
  t.timestamps
end
add_index :subscriptions, [:user_id, :status]
```

Every FK: `null: false`, `foreign_key: true`, `index: true`. Composite indexes for known query patterns. `strong_migrations` gem to block unsafe migrations.

---

## Middleware

```ruby
# config/application.rb
config.middleware.use Rack::Attack   # Rate limiting

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!          # Devise
  before_action :set_current_request_id
  after_action  :track_page_view
  private
  def set_current_request_id = Current.request_id = request.request_id
end

# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :set_subscription, only: [:show, :cancel]
  private
  def set_subscription
    @subscription = current_user.subscriptions.find(params[:id])  # Scoped — prevents IDOR
  end
end
```

Always scope finds to `current_user` (never bare `Subscription.find` — that is an IDOR vulnerability). Use `only:`/`except:` on every filter. Avoid `around_action` — it obscures control flow.

---

## Authentication

**Devise** is the default. Not elegant, but battle-tested — handles password resets, email confirmation, account lockout, sessions. Customize views on Day 1 (`rails generate devise:views`).

```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable, :confirmable, :lockable
end
```

**`has_secure_password`** for API-only or when Devise is overkill. Uses bcrypt. Do not roll your own hashing.

```ruby
class User < ApplicationRecord
  has_secure_password
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  normalizes :email, with: ->(e) { e.strip.downcase }
end
```

---

## Template Patterns

ERB is the default. Do not switch to Haml or Slim for aesthetics — ERB is what every Rails developer knows. Hotwire (Turbo + Stimulus) is the answer to "I want SPA-like UX without a JS framework."

```erb
<%# Turbo Frame — replaces only this section on navigation %>
<%= turbo_frame_tag dom_id(@subscription) do %>
  <h1><%= @subscription.plan.name %></h1>
  <span class="badge badge-<%= @subscription.status %>"><%= @subscription.status.humanize %></span>
  <% if @subscription.active? %>
    <%= button_to "Cancel", cancel_subscription_path(@subscription), method: :post,
        data: { turbo_confirm: "Cancel at end of billing period?" } %>
  <% end %>
<% end %>
```

```ruby
# Turbo Stream response — controller responds with partial page update
def cancel
  result = Subscriptions::CancelService.call(subscription: @subscription, user: current_user)
  result.success? ? respond_to { |f| f.turbo_stream; f.html { redirect_to @subscription } }
                  : redirect_to(@subscription, alert: result.error)
end
```

**Stimulus** for behavior Turbo cannot handle (toggles, clipboard, form interactivity). **ViewComponent** for UI elements that need logic, tests, or previews — use over partials for anything non-trivial.

---

## API Patterns

Generate with `rails new my_api --api` to strip views, cookies, CSRF, and asset pipeline.

```ruby
module Api::V1
  class BaseController < ActionController::API
    before_action :authenticate_api_user!
    rescue_from ActiveRecord::RecordNotFound, with: -> { render_error("not_found", 404) }
    private
    def authenticate_api_user!
      token = request.headers["Authorization"]&.remove("Bearer ")
      @current_user = User.find_by(api_token: token)
      render_error("unauthorized", 401) unless @current_user
    end
    def render_error(code, status)
      render json: { error: { code: code }, meta: { request_id: request.request_id } }, status: status
    end
  end

  class SubscriptionsController < BaseController
    def index
      pagy, records = pagy(@current_user.subscriptions.includes(:plan))
      render json: { data: records.as_json(include: :plan), meta: pagy_metadata(pagy) }
    end

    def create
      result = Subscriptions::CreateService.call(
        user: @current_user, plan_id: params.require(:plan_id),
        payment_method_id: params.require(:payment_method_id)
      )
      result.success? ? render(json: { data: result.subscription }, status: :created)
                      : render(json: { error: { code: "creation_failed", message: result.error } }, status: 422)
    end
  end
end
```

**Versioning:** always `/api/v1/` with namespaced controllers. When v2 ships, keep v1 intact — no conditionals. **Serialization:** inline or `Alba`. Avoid `jbuilder` (slow, hard to test).

---

## Testing Strategy

RSpec + FactoryBot. Non-negotiable.

```ruby
# spec/factories/subscriptions.rb
FactoryBot.define do
  factory :subscription do
    user; plan
    status { "active" }
    current_period_start { Time.current }
    current_period_end   { 30.days.from_now }
    stripe_subscription_id { "sub_#{SecureRandom.hex(12)}" }
    trait(:cancelled) { status { "cancelled" }; cancelled_at { Time.current } }
  end
end

# spec/services/subscriptions/cancel_service_spec.rb — HIGHEST VALUE TESTS
RSpec.describe Subscriptions::CancelService do
  let(:user) { create(:user) }
  let(:subscription) { create(:subscription, user: user) }
  let(:stripe) { instance_double(Adapters::Stripe, cancel_subscription: true) }
  before { allow(Adapters::Stripe).to receive(:new).and_return(stripe) }

  it "cancels and notifies Stripe" do
    result = described_class.call(subscription: subscription, user: user)
    expect(result).to be_success
    expect(subscription.reload.status).to eq("cancelled")
    expect(stripe).to have_received(:cancel_subscription)
  end

  it("rejects unauthorized users") { expect(described_class.call(subscription: subscription, user: create(:user))).not_to be_success }
end

# spec/requests/api/v1/subscriptions_spec.rb — API CONTRACT TESTS
RSpec.describe "Api::V1::Subscriptions" do
  let(:user) { create(:user, api_token: "tok_123") }
  let(:headers) { { "Authorization" => "Bearer tok_123" } }

  it "returns only the user's subscriptions" do
    create_list(:subscription, 3, user: user); create(:subscription)
    get "/api/v1/subscriptions", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"].length).to eq(3)
  end
end
```

**Pyramid:** service specs (most — all business logic, fast) > request specs (API contracts, one happy + one error per endpoint) > model specs (validations, scopes) > system specs (fewest — critical journeys only, they are slow).

---

## Deployment (Walking Skeleton)

If any item is missing, stop feature work and finish the skeleton:

1. **Puma** — `WEB_CONCURRENCY` matches CPU cores, `RAILS_MAX_THREADS=5`, DB pool matches threads
2. **Dockerfile** — multi-stage build, assets in builder stage, `ruby:3.3-slim` runtime
3. **Asset pipeline** — Propshaft (Rails 8 default), precompiled in Docker, served via CDN — never Puma
4. **Heroku / Render** — deploy-on-push from main, `RAILS_ENV=production`, `RAILS_LOG_TO_STDOUT=true`
5. **PostgreSQL** — provisioned, `rails db:migrate` as release command, never manually
6. **Sidekiq + Redis** — in `Procfile`, enqueue a test job, verify it processes
7. **Sentry** — gem installed, DSN configured, trigger test error, verify it appears

---

## Rails-Specific Quality Checklist

- [ ] **Skinny controllers** — no action exceeds 10 lines. Extract a service if it does.
- [ ] **Eager loading** — every collection uses `includes()`. Run `Bullet` gem in development.
- [ ] **Strong parameters** — permit only exact params needed. Never `permit!`.
- [ ] **Database indexes** — every FK indexed. Every `WHERE`/`ORDER BY` column on list pages indexed. Run `lol_dba`.
- [ ] **No side effects in callbacks** — callbacks set internal state only. Side effects live in services.
- [ ] **String enums** — `enum :status, { active: "active" }`, not `[:active]`. Integers are unreadable and dangerous to reorder.
- [ ] **Encrypted credentials** — secrets in `rails credentials:edit`, not plain-text config or committed env files.
- [ ] **Background jobs for slow work** — anything >300ms (emails, Stripe calls, PDFs) runs in Sidekiq.
- [ ] **UTC everywhere** — `Time.current` and `Date.current`, never `.now` or `.today`.
- [ ] **Strong Migrations** — gem installed, blocking unsafe migrations (column removal, non-concurrent indexes).

---

## Common Failure Modes

| Failure Mode | Symptom | Fix |
|---|---|---|
| **N+1 queries** | Hundreds of SELECTs per request, 2-5s page loads | `includes(:association)`. Install `Bullet` gem. |
| **Fat controllers** | 30+ line actions, duplicated logic, tests require full HTTP setup | Extract service objects. Controller calls service, returns result. |
| **Callback hell** | Record creation triggers emails, Stripe calls, cache busting. Tests fail mysteriously. | Move side effects to services. Callbacks only set internal model state. |
| **Missing indexes** | List pages degrade as data grows. `EXPLAIN` shows seq scans. | Index FKs, filtered columns, sort columns. `lol_dba` gem to audit. |
| **`permit!` params** | Mass-assignment of `role`, `is_admin`, `price_cents` | Explicitly permit only user-settable fields. Never `permit!`. |
| **Monolith models** | `User.rb` is 500+ lines with 30 associations | Extract concerns for cohesive behavior groups. Query objects for complex scopes. |
| **No service layer** | Logic scattered across controllers, models, jobs. No entry point for "cancel a subscription." | `app/services/` from Day 1. One class per operation. One public method (`.call`). |
| **Unversioned API** | Changes break mobile clients in production | Namespace under `/api/v1/`. Create `v2` controllers for breaking changes. |
