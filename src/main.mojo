"""The whole program from "Writing ergonomic multithreaded code in Mojo 1.0".

https://magmalake.org/blog/writing-multithreaded-code-in-mojo/

`parallel_for` starts one thread per core, hands each of them indices from a
shared atomic counter until the tasks are gone, and joins every thread before
it returns. `task` runs on every core; `totals` is a plain struct on `main`'s
stack that every thread updates through the one pointer a thread can carry.
"""

from threads import AtomicCounter, OpaquePtr, num_cpus, parallel_for


@fieldwise_init
struct Ctx[T: AnyType](Copyable, Movable):
    """A typed view of the pointer each task is handed.

    `Ctx[T].to(state)` on the calling side, `Ctx[T].of(ptr)` inside the task,
    and in between an ordinary struct with named fields. It types the sharing;
    it does not synchronise it — `MutUntrackedOrigin` is the annotation saying
    so.
    """

    var _ptr: Pointer[Self.T, MutUntrackedOrigin]

    @staticmethod
    def to(ref state: Self.T) -> Self:
        return Self(
            Pointer[Self.T, MutUntrackedOrigin](
                unsafe_from_address=Int(Pointer(to=state))
            )
        )

    @staticmethod
    def of(ptr: OpaquePtr) -> Self:
        return Self(
            Pointer[Self.T, MutUntrackedOrigin](unsafe_from_address=Int(ptr))
        )

    def __getitem__(self) -> ref[MutUntrackedOrigin] Self.T:
        return self._ptr[]

    def opaque(self) -> OpaquePtr:
        return OpaquePtr(unsafe_from_address=Int(self._ptr))


@fieldwise_init
struct Totals(Copyable, Movable):
    var sum: Int64


def counter(ref cell: Int64) -> AtomicCounter:
    """`AtomicCounter` is a view over a cell, not a counter that owns storage.

    The struct owns a plain `Int64`; the view borrows its address and performs
    atomic operations on it. Take a view where you need one, do not keep it.
    """
    return AtomicCounter.at(Int(Pointer(to=cell)))


def task(i: Int, ptr: OpaquePtr) -> None:
    """The work function: a top-level `def`, because a thread body must be thin.

    Everything it needs arrives through the one pointer argument.
    """
    var t = Ctx[Totals].of(ptr)
    _ = counter(t[].sum).fetch_add(Int64(i))


def main() raises:
    var totals = Totals(0)
    parallel_for[task](1000, Ctx[Totals].to(totals).opaque())
    print("cores:", num_cpus(), " sum:", totals.sum)
