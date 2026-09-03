# Not a lifetime bug: a data race. `Ctx.__getitem__` hands every task a
# mutable ref to the same `Totals`, and nothing stops a task writing to
# `sum` with a plain load and store instead of the atomic. Rust rejects this
# before threads come into it — `&mut` aliased across closures is an
# exclusivity error, and the atomic works through `&AtomicI64` because that
# type is `Sync`. Mojo has no interior-mutability marker, so there is no way
# for `share` to demand one; the origin says only how long `totals` lives.
#
# The window between load and store is widened on purpose so that the lost
# updates are a certainty rather than a likelihood, and the worker count is
# fixed so a single-core runner cannot serialise the tasks by accident.
# expect: plain store, lost updates: True
from std.time import perf_counter_ns
from origins import Ctx, run, share
from threads import OpaquePtr


@fieldwise_init
struct Totals(Copyable, Movable):
    var sum: Int64


def task(i: Int, ptr: OpaquePtr) -> None:
    var t = Ctx[Totals].of(ptr)
    var seen = t[].sum
    var t0 = perf_counter_ns()
    while perf_counter_ns() - t0 < 20_000:
        pass
    t[].sum = seen + Int64(i)


def main() raises:
    var totals = Totals(0)
    run[task](1000, share(totals), num_workers=4)
    print("plain store, lost updates:", totals.sum != 499500)
