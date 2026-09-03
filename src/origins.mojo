"""The post's program with the origin kept, not erased.

https://magmalake.org/blog/writing-multithreaded-code-in-mojo/

`post.mojo` builds its context with `MutUntrackedOrigin` from the first line,
which tells the compiler nothing about how long `totals` has to live. That is
a real hole: a value is destroyed at its last use, and if the only later use
is through an untracked pointer the compiler cannot see, the last visible use
is `Ctx[Totals].to(totals)` — before `parallel_for` runs. With a `Totals` that
owns heap memory, a thousand tasks then write into a freed block.

Here `totals` goes to `parallel_for` as a `ref` argument and reaches every
task as `mut`. An argument is alive for the whole call, joins included, so
the compiler extends the lifetime of `totals` to cover it with no later use
required; and a `ref` demands a mutable binding, so a `read` argument or a
temporary is rejected where the call is made. The erasure to `void *` still
happens — a pthread carries one pointer — but once, inside the library, and
nothing in this file handles it.

An earlier version of this file did the same job in user code: a
`Ctx[T, origin]` built by `share(totals)` and held across the call by
`run[task](n, ctx)`. threads-mojo 0.3.0 moved that into `parallel_for`
itself, which is why the program below is the post's listing minus the
pointer plumbing.
"""

from threads import AtomicCounter, num_cpus, parallel_for


@fieldwise_init
struct Totals(Copyable, Movable):
    var sum: Int64


def counter(ref cell: Int64) -> AtomicCounter:
    """`AtomicCounter` is a view over a cell; it owns no storage."""
    return AtomicCounter.at(Int(Pointer(to=cell)))


def task(i: Int, mut totals: Totals) -> None:
    """The work function: a top-level `def`, since a thread body is thin.

    Every task gets `mut` access to the same `Totals` at the same time; the
    atomic is what makes that honest. A plain `totals.sum += i` would compile
    just as well — see `tests/uncaught/plain_store_races.mojo`.
    """
    _ = counter(totals.sum).fetch_add(Int64(i))


def main() raises:
    var totals = Totals(0)
    parallel_for[task](1000, totals)
    print("cores:", num_cpus(), " sum:", totals.sum)
