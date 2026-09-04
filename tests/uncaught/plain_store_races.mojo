# Not a lifetime bug: a data race. `parallel_for` hands every task `mut`
# access to the same `Totals`, and nothing stops a task writing to `sum`
# with a plain load and store instead of the atomic. Rust rejects this
# before threads come into it — `&mut` aliased across closures is an
# exclusivity error, and the atomic works through `&AtomicI64` because that
# type is `Sync`. Mojo has no interior-mutability marker, so there is no way
# for `parallel_for` to demand one; the origin says only how long `totals`
# lives.
#
# The window between load and store is widened on purpose so that the lost
# updates are a certainty rather than a likelihood, and the worker count is
# fixed so a single-core runner cannot serialise the tasks by accident.
# expect: plain store, lost updates: True
# Two threads, a plain load and a plain store, no ordering between them: this
# is the one case here a race detector can see, and `--sanitize thread` names
# both accesses inside `_parallel_worker`. The lint (L003) and the sanitizer
# agree, from opposite ends.
# expect-tsan: race
from std.time import perf_counter_ns
from threads import parallel_for


@fieldwise_init
struct Totals(Copyable, Movable):
    var sum: Int64


def task(i: Int, mut t: Totals) -> None:
    var seen = t.sum
    var t0 = perf_counter_ns()
    while perf_counter_ns() - t0 < 20_000:
        pass
    t.sum = seen + Int64(i)


def main() raises:
    var totals = Totals(0)
    parallel_for[task](1000, totals, num_workers=4)
    print("plain store, lost updates:", totals.sum != 499500)
