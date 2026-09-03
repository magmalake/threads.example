# Same refusal, one scope down: `t` dies with the block, `c` does not.
# expect-error: cannot implicitly convert 'Ctx[Totals, origin_of(t)]' value to 'Ctx[Totals]'
from origins import Ctx, Totals, run, share, task


def main() raises:
    var c: Ctx[Totals]
    var n = 1
    if n == 1:
        var t = Totals(0)
        c = share(t)
    run[task](1000, c)
    print(c[].sum)
