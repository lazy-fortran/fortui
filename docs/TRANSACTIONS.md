# Transactions and commands

These are target contracts. The existing explicit frame loop is a prototype;
[PLAN.md](../PLAN.md) tracks implementation and behavioral evidence. Names below
are conceptual until a milestone establishes an actual public API.

## Transaction definition

A semantic transaction is one serialized application update/composition boundary,
identified by a monotonic transaction ID. It contains an accepted input operation
or a coalesced invalidation/service update. It is distinct from an OS event,
display refresh, physical gesture, and document undo record.

The scheduler executes application composition exactly once for each transaction
that reaches the composition phase. Rejected/stale events can be discarded before
creating a transaction. A failed composition is attempted once and reported; it is
not retried automatically. There is no speculative composition or nested execution.

A transaction may perform multiple measurement/reconciliation/render operations
without executing composition again. Accessibility queries read the published
semantic state. Painting uses runtime state and does not execute application code.

## Event path and phases

```text
platform event / service completion / explicit invalidation
    -> owned normalized event with sequence, origin and generation
    -> eligibility and routing against last realized revision
    -> command dispatch or inline event mailbox
    -> exactly one application composition
    -> validate semantic frame and reconcile identities
    -> measure/layout and realize
    -> publish semantic + realized revision
    -> schedule any separately required follow-up
```

Each normalized event records device/window identity, sequence, target generation,
and coordinates or typed value data. Pointer coordinates include their source
space. Routing uses the last realized geometry, including host transforms, clipping,
scroll offsets, and native/DOM bounds. It must not guess from a newer unpublished
layout. Native control callbacks use stable handles with generation checks.

Do not collapse two clicks, two commands, or text edits into one boolean. Schedule
separate activation transactions or use an explicit ordered operation queue.
Pointer-motion events may coalesce only where intermediate samples are unnecessary;
stylus strokes and velocity/gesture recognition may need all samples. Releases,
cancellation, and discrete actions keep their order.

## Activation delivery

An activation has a unique token. Once consumed by its inline target or command
owner, it cannot be delivered again in later compositions. A follow-up transaction
has no inherited activation. Disabling/removing/replacing the target cancels pending
activation according to dispatch policy; recycled keys cannot receive old events.

This provides at-most-once delivery within a running process. It does not promise
exactly-once external effects, crash recovery, persisted command deduplication,
or delivery of every OS event. Applications requiring durable jobs own that protocol.

Runtime requests and user code must not execute composition recursively. Events
arriving during a transaction are queued for a later boundary. Modal OS surfaces
must not create nested application composition through a hidden event loop.

## Inline composition and freshness

The simple style is valid:

```fortran
call text("status", status_for(document%dirty))
if (button("save", "Save")) call save_document()
```

If save clears `dirty`, the already emitted status still describes the earlier
state. The framework cannot repair it by rerunning this routine in the same
transaction. Any consumed inline activation or changed value control schedules a
single coalesced follow-up transaction. It describes post-handler state, without
replaying the activation. Further asynchronous changes request their own update.

The first description may be a transient mixed-state frame; this is a documented
cost of inline mutations. A backend may skip its paint when a refresh is pending,
but must preserve ordered interaction and release state. Applications requiring
one coherent post-command publication should dispatch commands before composition.

An inline handler must not depend on being called again. An ordinary assignment
to a Fortran scalar does not automatically invalidate the UI. External domain changes
explicitly request an update or advance an observed application revision.
Composition itself must not request another update unconditionally; diagnose
persistent rescheduling and report it rather than inventing a convergence loop.

## Command ownership

An action descriptor has a stable action ID, label, description, enabled/checked
presentation, shortcut intent, and optional owned parameter schema. A registration
chooses one execution mechanism: registered handler or application dispatcher.
Duplicate execution ownership is a diagnostic. Registration precedes use and is
scoped to the application/window as appropriate; composition updates metadata.

Action-bound buttons, menus, shortcuts, palettes, touch controls, and accessibility
operations enqueue the same command intent. They never ask inline application code
to execute that command a second time. Separate action-control subroutines are
preferred to an ambiguous `if (button(action=...)) call save()` convention.

The selected dispatcher executes before composition and validates current domain
eligibility. Last published `enabled` is a presentation/routing hint; the operation
must still reject stale requests safely. Guards may inspect current domain state;
FortUI cannot observe arbitrary Fortran expressions automatically. Parameter payloads
are owned, typed, and validated before mutation.

One physical shortcut is routed through one owner even if the OS menu, DOM control,
and application shortcut machinery can all observe it. Platform-reserved shortcuts
and text-editing shortcuts have explicit priority. Shortcut descriptions are
portable intent, not an assumption that Ctrl is the primary modifier everywhere.

A command completion reports accepted/rejected/cancelled/failed and resulting domain
revision when available. Document history grouping belongs to the application:
one drag can produce many transactions and one undo record. Runtime text editing
history and document history have explicit focus-based routing.

## Asynchronous operations

A platform request has an ID, originating action/transaction, owner window/document
generation, owned payload, and cancellation state. Backend completion enqueues an
owned result; application state changes occur on the serialized application path.
A completion for a closed document/window is stale and discarded with a trace.

File pickers, save jobs, permissions, clipboard requests, sharing, and TeX preview
may be asynchronous. Domain work uses application-owned data or snapshots; workers
do not mutate the composing document. Completion revision checks prevent an older
preview/save result overwriting newer state. Save success clears dirty only for the
revision actually saved. No worker retains a borrowed widget argument.

Browser transient user activation is special: a privileged operation may need to
start directly in the trusted native event handler. A backend can launch a previously
declared operation or reserve the permitted platform interaction and later deliver
its result. It must report when deferred execution cannot satisfy the browser;
FortUI must not claim arbitrary inline calls preserve activation indefinitely.

## Publication, failure, and shutdown

Build the semantic frame privately. Validate identities and required metadata before
publishing it. A malformed frame does not replace the last valid semantic revision.
Expose diagnostics through headless inspection and the application's error path.

A command/domain mutation may already have occurred when composition or realization
fails. Do not roll back or retry application side effects implicitly. Keep a failure
record and require an explicit recovery transaction. Backend realization failure
can require rebuilding native resources; an explicit backend request never silently
changes into another backend. A last valid frame may be visibly stale after failure.

Shutdown cancels owned requests, releases capture/editing resources, and disconnects
callbacks before destroying handles. Recycled handle IDs include new generations.
Requested shutdown cannot be undone by a late asynchronous callback.

## Behavioral acceptance

Use independent counters and document expectations, not checks that source matches
the patch. Required cases include:

- One click executes one inline operation; a follow-up refresh updates an earlier
  dirty/status label without executing it again.
- Two queued clicks execute twice in order; duplicate observation of one shortcut
  executes once. A disabled action rejects a stale queued request.
- Layout/paint/accessibility queries do not increment the composition counter.
- An undoable drag groups several transactions into the specified history record.
- Reordered collection objects retain identity; removed/recycled objects reject
  delayed events and service completions.
- Save completion for revision N does not clear dirty after revision N+1.
- Composition failure does not retry a file write or publish a malformed frame.
- Idle consumes no application transactions; explicit invalidation wakes it.

Headless tests exercise normalized routing. Real platform tests must additionally
prove callback ordering, shortcut duplication handling, trusted activation, lifecycle,
and native event delivery. The prototype has not yet passed this complete suite.
