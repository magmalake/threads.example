"""The post's program with the origin kept, not erased.

https://magmalake.org/blog/writing-multithreaded-code-in-mojo/

`post.mojo` builds its context with `MutUntrackedOrigin` from the first line,
which tells the compiler nothing about how long `totals` has to live. That is
a real hole: a value is destroyed at its last use, and if the only later use
is through an untracked pointer the compiler cannot see, the last visible use
is `Ctx[Totals].to(totals)` — before `parallel_for` runs. With a `Totals` that
owns heap memory, a thousand tasks then write into a freed block.

Here the context carries the origin of the state it points to. `share`
captures it, `run` holds a value of that type across the `parallel_for`, and
the compiler extends the lifetime of `totals` to cover the call — no later use
of `totals` required. What the compiler will now reject: sharing an immutable
argument or a temporary, returning a `Ctx` to a local, and letting a `Ctx`
outlive its block.

The origin stops at `opaque()`. A pthread carries one `void *`, so the task
side gets it back through `Ctx[Totals].of(ptr)` with the untracked default —
inside a task the origin is genuinely unknowable. Keep `opaque()` as the one
place the erasure happens, inside `run`, and nothing else in the program needs
to reason about it.
"""

from threads import AtomicCounter, OpaquePtr, WorkFn, num_cpus, parallel_for


@fieldwise_init
struct Ctx[T: AnyType, origin: MutOrigin = MutUntrackedOrigin](
    Copyable, Movable
):
    """A typed view of the pointer each task is handed, with an origin.

    On the calling side the origin is the state's own — `share` builds one.
    Inside a task it defaults to `MutUntrackedOrigin`, because the pointer
    arrived through `void *` and there is nothing to track it against.
    """

    var _ptr: Pointer[Self.T, Self.origin]

    @staticmethod
    def of(ptr: OpaquePtr) -> Self:
        """The task-side view: reinterpret the opaque pointer as a `T`."""
        return Self(Pointer[Self.T, Self.origin](unsafe_from_address=Int(ptr)))

    def __getitem__(self) -> ref[Self.origin] Self.T:
        return self._ptr[]

    def opaque(self) -> OpaquePtr:
        """Erase the origin. The one operation the compiler cannot check."""
        return OpaquePtr(unsafe_from_address=Int(self._ptr))


def share[
    T: AnyType, origin: MutOrigin
](ref[origin] state: T) -> Ctx[T, origin]:
    """A `Ctx` whose origin is `state`'s own — `origin_of(state)`.

    Requires a mutable binding: an immutable argument or a temporary is
    rejected at the call site.
    """
    return Ctx[T, origin](Pointer(to=state))


def run[
    T: AnyType, origin: MutOrigin, //, work: WorkFn
](n_tasks: Int, ctx: Ctx[T, origin], num_workers: Int = 0) raises:
    """`parallel_for`, taking the tracked context rather than the pointer.

    `ctx` is alive for the whole call, so the state it points to is too. The
    erasure to `void *` happens here and nowhere else.
    """
    parallel_for[work](n_tasks, ctx.opaque(), num_workers)


@fieldwise_init
struct Totals(Copyable, Movable):
    var sum: Int64


def counter(ref cell: Int64) -> AtomicCounter:
    """`AtomicCounter` is a view over a cell; it owns no storage."""
    return AtomicCounter.at(Int(Pointer(to=cell)))


def task(i: Int, ptr: OpaquePtr) -> None:
    """The work function: a top-level `def`, since a thread body is thin."""
    var t = Ctx[Totals].of(ptr)
    _ = counter(t[].sum).fetch_add(Int64(i))


def main() raises:
    var totals = Totals(0)
    run[task](1000, share(totals))
    print("cores:", num_cpus(), " sum:", totals.sum)
