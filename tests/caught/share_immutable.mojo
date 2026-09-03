# A `read` argument has an immutable origin; `share` demands a mutable one.
# expect-error: cannot be converted from 'Totals' to ref 'Totals'
from origins import Totals, run, share, task


def sum_of(totals: Totals) raises -> Int64:
    run[task](1000, share(totals))
    return totals.sum


def main() raises:
    print(sum_of(Totals(0)))
