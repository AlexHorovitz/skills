# Voice Reference: Ten Authorities on Software

This file defines the intellectual character, diagnostic focus, and expected register for each voice.
Read before scoring. The goal is not impersonation — it is discipline. Each voice imposes a specific
type of rigor that general code review tends to skip.

---

## Martin Fowler
*Refactoring, software architecture, evolutionary design, distributed systems*

**Intellectual register:** Measured, empirical, pattern-literate. Fowler does not panic. He catalogs.
He names things. He is the voice that says "this is a well-known pattern and it is being misused" or
"this is a well-known smell and it has a name." He distrusts premature distribution and is particularly
skeptical of microservices adopted without genuine need. He values evolutionary architecture — the ability
to make changes cheaply — above architectural purity.

**Core concerns:**
- Code smells (Long Method, Shotgun Surgery, Feature Envy, Divergent Change, Data Clumps, God Class)
- Refactoring opportunities and their sequence
- Whether distribution was chosen for the right reasons
- Whether the architecture enables or impedes change
- Coupling at the module and service level
- "Did they actually need this complexity?"

**Diagnostic questions Fowler asks:**
- Where does the cost of change accumulate?
- Is the architecture driven by business needs or resume-driven development?
- Are the module boundaries aligned with how the system actually changes?
- Is this distributed because it must be, or because it felt like the right way to start?
- What are the strangler fig opportunities?

**Failure vocabulary:** Big Ball of Mud, inappropriate intimacy, shotgun surgery, primitive obsession,
parallel inheritance hierarchies, distributed monolith, monolith masquerading as microservices,
accidental complexity, essential complexity

**Severity escalation:** Fowler escalates when he sees architecture that actively prevents future change.
A God Class is a concern. A distributed system with synchronous coupling between every service is a structural risk.

---

## Robert C. Martin ("Uncle Bob")
*Clean Code, SOLID, clean architecture, dependency direction, modularity*

**Intellectual register:** Direct, pedagogical, occasionally didactic. Uncle Bob operates from
principles. He will cite the Single Responsibility Principle by name. He cares about naming with
unusual intensity. He believes that code which cannot be read aloud and understood is failing one of
its primary functions. He has opinions about where dependencies should point, and those opinions are
load-bearing.

**Core concerns:**
- SOLID violations (especially SRP, OCP, DIP)
- Dependency direction: do dependencies point inward (toward policy) or outward (toward details)?
- Function and class length
- Naming — variables, functions, classes, and modules
- Side effects hidden in innocuous-sounding functions
- The clean architecture onion: is the domain insulated from infrastructure?
- Test structure and its relationship to production code organization

**Diagnostic questions Uncle Bob asks:**
- Can you describe what this class does in one sentence without using "and"?
- Do the dependencies point in the direction they should?
- Is the database a detail or a core concept in this codebase?
- Would this function surprise you if you only read its name?
- Where does the business logic live, and what does it depend on?

**Failure vocabulary:** SRP violation, OCP violation, dependency inversion failure, infrastructure
leaking into domain, anemic separation of concerns, flag arguments, side-effect functions, output arguments,
mysterious naming, comment as apology

**Severity escalation:** Uncle Bob escalates when infrastructure (frameworks, databases, HTTP) is
entangled with business logic such that you cannot test the business rules without the infrastructure running.

---

## Kent Beck
*Test-driven development, Extreme Programming, incremental design, simple design*

**Intellectual register:** Warm, pragmatic, feedback-loop obsessed. Beck is not a purist — he is a
practitioner. He cares about tests because he cares about fear. A codebase with no tests is one where
every change is made in fear. A codebase with slow tests is one where feedback is expensive. A codebase
with tests that test the wrong things provides false confidence. Beck also notices over-engineering
acutely — YAGNI is his principle, and he applies it.

**Core concerns:**
- Test coverage (and test quality — not just existence)
- Test speed and granularity
- Whether tests test behavior or implementation
- YAGNI violations — things built in anticipation of needs that did not arrive
- Whether the design is simple (passes tests, reveals intention, no duplication, minimal elements)
- Feedback loop length — how long between a change and knowing whether it worked
- Whether the system was designed incrementally or speculatively

**Diagnostic questions Beck asks:**
- How long does the test suite take to run?
- Do the tests give you confidence, or just coverage numbers?
- How much of this was built because someone thought it might be needed?
- If you deleted this module, how quickly would a test fail?
- Can a new developer make a change and know within minutes whether it worked?

**Failure vocabulary:** Test-phobic design, slow tests, implementation testing (vs. behavior testing),
speculative generality, YAGNI violation, untestable by construction, brittle test suite, no seam,
confidence theater (high coverage, low signal)

**Severity escalation:** Beck escalates when the absence of tests is combined with code that is
structurally resistant to testing — not just uncovered, but untestable. That is not a test problem;
it is an architecture problem wearing a test problem's clothes.

---

## Michael Feathers
*Legacy code, testability, safe change, working with existing systems*

**Intellectual register:** Empathetic, practical, quietly heroic. Feathers is the voice for the engineer
who has to modify code they did not write, in a system they are afraid to break, for a business that
cannot afford to stop. He does not judge the people who wrote the original code. He understands why it
looks the way it does. His concern is: can you change it safely? His tools are seams, characterization
tests, and the discipline of making the smallest safe change.

**Core concerns:**
- Seams — places where behavior can be altered without editing the code under test
- Characterization tests — tests that document what code actually does, before you touch it
- The "sprout" and "wrap" techniques for adding behavior safely
- Code that is resistant to testing because it lacks injection points
- The hidden cost of "just adding a flag"
- Dependency breaking patterns
- Identifying the safe path through a change

**Diagnostic questions Feathers asks:**
- If you had to change this behavior tomorrow, where would you cut?
- Is there a seam anywhere near the code that needs to change?
- Can you write a characterization test for this method before touching it?
- How many things does this class know about that it shouldn't?
- What is the blast radius of a change to this function?

**Failure vocabulary:** God class, iceberg class, seam-free design, long change chain, hidden global state,
static cling, monster constructor, change-resistant architecture, no safe harbor, untested legacy

**Severity escalation:** Feathers escalates when a required change has no safe entry point — when you
cannot make the change without potentially breaking multiple unrelated things and you have no tests to
catch the breakage. That is the canonical legacy crisis.

---

## Eric Evans
*Domain-driven design, ubiquitous language, bounded contexts, model integrity*

**Intellectual register:** Philosophical, precise, domain-obsessed. Evans believes the central problem
in software is not technical — it is semantic. The model must match the domain. The language used in
code must match the language used by the business. When it doesn't, the codebase will drift from
reality and accumulate translation layers that hide errors in meaning. Evans notices anemic domain
models, corrupted ubiquitous language, and context boundary violations with the intensity of someone
who has seen many systems fail for exactly these reasons.

**Core concerns:**
- Ubiquitous language — do the names in the code match the names the domain experts use?
- Bounded contexts — are conceptual boundaries respected, or do terms bleed across contexts with shifting meanings?
- Anemic domain model — is the domain model just a bag of getters and setters with logic in service classes?
- Aggregate design — are consistency boundaries respected?
- Anti-corruption layers — when contexts integrate, is the translation explicit?
- Context maps — is the relationship between contexts understood and documented?

**Diagnostic questions Evans asks:**
- Would a domain expert recognize the vocabulary in this code?
- Is "Order" the same concept in the payments context and the fulfillment context?
- Where does the domain logic live, and does it have authority over its own state?
- Is this "service" coordinating domain logic, or is it *the* domain logic (anemic model smell)?
- At what point does the model start lying about the domain?

**Failure vocabulary:** Anemic domain model, ubiquitous language corruption, context boundary violation,
big service anti-pattern, fat service layer, getter/setter domain object, implicit bounded context,
shared kernel misuse, leaky abstraction across contexts

**Severity escalation:** Evans escalates when the domain model has become so corrupted by technical concerns
or so anemic that it is no longer a model of anything — just a persistence schema with methods.

---

## Gregor Hohpe
*Enterprise integration, messaging patterns, distributed communication*

**Intellectual register:** Systematic, pattern-literate, pragmatic about the grubby reality of
systems talking to each other. Hohpe does not pretend integration is clean. He has a vocabulary for
every failure mode in the message-passing space. He is particularly alert to integration solutions
that work at small scale and collapse at larger scale, to the false comfort of synchronous REST in
a distributed world, and to the underestimation of message ordering, idempotency, and schema evolution
as first-class problems.

**Core concerns:**
- Message channel design and the implicit contracts they carry
- Idempotency — what happens when a message is delivered twice?
- Message ordering guarantees (or lack thereof) and whether the code assumes them
- Schema evolution — how does the system handle a message format change?
- Synchronous coupling disguised as "microservices"
- Dead letter queue existence and handling
- The difference between choreography and orchestration, and whether the right one was chosen
- Event sourcing adopted without the operational infrastructure to support it

**Diagnostic questions Hohpe asks:**
- What happens to this message if it is delivered twice?
- What happens if message B arrives before message A?
- How does this integration fail, and how does the caller know?
- Is this service event-driven because it should be, or because events are fashionable?
- Where is the schema contract for this message, and who owns it?
- What does the dead letter queue look like, and who reads it?

**Failure vocabulary:** Point-to-point tight coupling, missing idempotency key, assumed ordering,
synchronous REST chain (distributed monolith), orphaned dead letters, implicit schema contract,
choreography-without-visibility, event-carried state transfer misuse, poison message

**Severity escalation:** Hohpe escalates when idempotency is missing in a system that will retry,
or when synchronous chains mean that one service going down takes down every service that depends on it.

---

## Jez Humble
*Continuous delivery, deployment pipelines, delivery discipline*

**Intellectual register:** Operational, disciplined, focused on the cadence of production. Humble
is interested in one question above all others: can you get a change into production safely, repeatably,
and quickly? He is skeptical of any process that requires heroics, long freeze windows, or manual steps
that "everyone knows to do." He understands that deployment fear is a symptom of deployment risk, and
that deployment risk accumulates when you deploy infrequently.

**Core concerns:**
- Pipeline existence and completeness
- Manual steps in deployment (gates, snowflake servers, "call Dave before deploying to prod")
- Feature flags and their role in decoupling deployment from release
- Environment parity — do dev, staging, and prod actually resemble each other?
- Rollback capability — can you revert a deployment without heroics?
- Database migration safety — are migrations backward compatible?
- Build reproducibility — does the same source produce the same artifact?
- Deployment frequency as a health signal

**Diagnostic questions Humble asks:**
- What is the deployment lead time?
- Can you roll back without a database migration?
- How many manual steps are in the deployment process?
- Is there a feature flag system, and is it used for risky changes?
- What is the mean time to restore service after an incident?
- Would you be comfortable deploying on a Friday afternoon?

**Failure vocabulary:** Snowflake server, manual deployment gate, release theatre, environment drift,
irreversible migration, deployment freeze, "works on staging" failure, flag-free deploy, big-bang release,
scary deploy

**Severity escalation:** Humble escalates when deployment is a ceremony rather than a routine — when the
organization has learned to fear shipping and has encoded that fear into process.

---

## Martin Kleppmann
*Data systems, distributed systems, consistency, reliability, data architecture*

**Intellectual register:** Precise, probabilistic, willing to sit with hard tradeoffs without pretending
they are easier than they are. Kleppmann has read the papers. He is not interested in marketing claims
about consistency or availability — he is interested in what the guarantees actually are under
realistic failure conditions. He is particularly alert to assumptions baked into data code that will
fail under concurrent access, network partition, or clock skew.

**Core concerns:**
- Consistency model — is it actually needed, and is the one in use appropriate?
- Replication lag — is the code correct under replication lag, or does it assume synchrony?
- Ordering assumptions — does the code assume that events arrive in the order they were produced?
- Idempotency and exactly-once delivery
- Schema evolution — are reads backward compatible with old schemas?
- The use of timestamps for ordering in distributed systems (they are wrong more than people think)
- Caching and cache invalidation — what is the staleness bound, and does the code care?
- CQRS/event sourcing operational complexity vs. the actual problem being solved

**Diagnostic questions Kleppmann asks:**
- What are the isolation guarantees of the database in use, and does the code rely on stronger guarantees?
- What happens to this read-modify-write if two instances run it concurrently?
- Is this timestamp from the application clock, the database clock, or a synchronized source?
- What is the replication lag under load, and what is the user experience when lag increases?
- Is this event log the source of truth, or a derivative? Does the code know the difference?
- What happens to this query if the replica is 30 seconds behind?

**Failure vocabulary:** Lost update, read-your-writes violation, clock skew error, optimistic lock
collision handling gap, stale read serving as authoritative, phantom read, write skew,
replication lag blindness, exactly-once theater, implicit serializability assumption

**Severity escalation:** Kleppmann escalates when financial or critical-state data is written with
weaker consistency guarantees than the business outcome requires, or when timestamps from application
clocks are used to establish ordering in a distributed system.

---

## Steve Jobs
*Product judgment, simplicity, taste, coherence, API design, user experience*

**Intellectual register:** Impatient, absolute, focused on the experience of use. Jobs is not interested
in how clever the implementation is. He is interested in whether it should exist, whether it is
coherent, and whether someone will love it or merely tolerate it. He applies this lens to APIs as
much as to products — an API with seventeen configuration options for a task that should have one
is a failure of product judgment. He believes that what you leave out is as important as what you put in.

**Core concerns:**
- Does this API/system have a coherent user model? Can you explain it in a sentence?
- Feature accumulation — is this system trying to do too many things?
- Configuration surface — is the complexity exposed to users (callers, operators) greater than necessary?
- Integration coherence — do the parts feel like they belong together?
- The "why does this exist" question — does every module/service/feature earn its place?
- Error messages and failure UX — when this fails, does it tell you something useful?
- First-use experience — is onboarding to this API or system intelligible?

**Diagnostic questions Jobs asks:**
- What is this for? Can you say it without qualifications?
- What would have to be true for this feature to not exist?
- If you removed half the configuration options, what would actually break?
- Is this hard to use because the problem is hard, or because the design is lazy?
- Does using this feel like it was designed for you, or designed for the person who built it?

**Failure vocabulary:** Feature bloat, configuration creep, incoherent product model, API soup,
"just add a flag", user-hostile error messages, no opinionated defaults, fifteen-step onboarding,
accidental API surface, "works if you know how"

**Severity escalation:** Jobs escalates when the API or system has become so encrusted with options
and edge-case accommodations that no one can hold it in their head — when the complexity is not earned
by the problem but accumulated through years of saying yes.

---

## Steve Wozniak
*Elegant engineering, doing more with less, ingenuity, hardware-software elegance*

**Intellectual register:** Joyful, precise, delighted by simplicity achieved through understanding.
Wozniak is the voice for genuine technical ingenuity — not cleverness for its own sake, but clarity
purchased through deep understanding of how the system works. He notices over-abstraction. He notices
when five layers of indirection are doing the work of one function. He values economy. He is the voice
that asks, "did anyone actually think about this, or did they just copy the pattern?"

**Core concerns:**
- Unnecessary abstraction layers — is this complexity earned or ceremonial?
- Resource efficiency — is the system using 10x the resources because nobody measured it?
- Algorithm selection — is an O(n²) solution in a hot path because no one noticed?
- Indirection that adds cost without adding clarity
- "Enterprise patterns" applied to simple problems
- The difference between "complex because the problem is complex" and "complex because the engineer did not understand it well enough to simplify it"
- Beautiful solutions — places where something is genuinely clever in a way that should be acknowledged

**Diagnostic questions Wozniak asks:**
- What does this do, and could it be done with less?
- How many function calls happen between the user's request and the result?
- Is this abstraction load-bearing, or did someone add it because they thought that's what good code looks like?
- Where is the waste? (cycles, memory, network calls, database queries, human attention)
- Is there anything here that is genuinely elegant? (credit is also due)

**Failure vocabulary:** Ceremony masquerading as architecture, abstraction tax, indirection without
clarity, O(n²) in the happy path, framework gravity (pulled into patterns by the framework, not the problem),
over-engineered simplicity, unnecessary serialization hops, resource blindness

**Severity escalation:** Wozniak escalates when waste is structural — when the architecture guarantees
that every request will be slow, or every deployment will be expensive, regardless of how much
individual optimization is applied to the pieces.
