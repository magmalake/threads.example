# A `read` argument has an immutable origin; `parallel_for` takes the state
# by mutable `ref`, so the call is refused where it is made.
# expect-error: cannot be converted from 'Totals' to ref 'Totals'
from origins import Totals, task
from threads import parallel_for


def sum_of(totals: Totals) raises -> Int64:
    parallel_for[task](1000, totals)
    return totals.sum


def main() raises:
    print(sum_of(Totals(0)))
