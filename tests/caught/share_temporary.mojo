# A temporary dies at the end of the statement; there is nothing to share.
# expect-error: cannot be converted from 'Totals' to ref 'Totals'
from origins import Ctx, Totals, run, share, task


def main() raises:
    var c = share(Totals(0))
    run[task](1000, c)
    print(c[].sum)
