# `share(t)` has type `Ctx[Totals, origin_of(t)]`, and the compiler will not
# quietly widen that to the untracked origin on the way out of the function.
# expect-error: cannot implicitly convert 'Ctx[Totals, origin_of(t)]' value to 'Ctx[Totals]'
from origins import Ctx, Totals, run, share, task


def make() -> Ctx[Totals]:
    var t = Totals(0)
    return share(t)


def main() raises:
    var c = make()
    run[task](1000, c)
    print(c[].sum)
