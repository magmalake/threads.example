# The tracked `Ctx` fixes the drop — until `opaque()` is called outside `run`.
# The `void *` carries no origin, the temporary `Ctx` dies with the statement,
# and `totals` goes with it. This is the boundary of what origins can cover.
# expect: Totals dropped
# expect: before parallel_for
# expect: after parallel_for: 499499
from std.memory.alloc import unsafe_alloc
from origins import Ctx, share
from threads import AtomicCounter, OpaquePtr, parallel_for


struct Totals(Movable):
    """Owns one heap cell and announces its own destruction.

    `__deinit__` poisons the cell to -1 instead of freeing it: a write into a
    freed block is undefined behaviour and corrupts the heap on some runs,
    while a write into a poisoned, leaked block is a number we can assert.
    """

    var cell: Pointer[Int64, MutUntrackedOrigin]

    def __init__(out self):
        self.cell = unsafe_alloc[Int64](1)
        self.cell[] = 0

    def __deinit__(deinit self):
        print("Totals dropped")
        self.cell[] = -1


def task(i: Int, ptr: OpaquePtr) -> None:
    var t = Ctx[Totals].of(ptr)
    _ = AtomicCounter.at(Int(t[].cell)).fetch_add(Int64(i))


def main() raises:
    var totals = Totals()
    var ptr = share(totals).opaque()
    print("before parallel_for")
    parallel_for[task](1000, ptr)
    # Not `totals.cell` — a use of `totals` here would move the drop past it.
    print("after parallel_for:", Ctx[Totals].of(ptr)[].cell[])
