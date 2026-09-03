# The typed `parallel_for` fixes the drop — the opaque one does not. `Int(…)`
# turns a pointer whose origin is `totals`'s own into a number, the number
# into an untracked `OpaquePtr`, and from there the compiler sees no use of
# `totals`, so it is destroyed on the spot. This is the boundary of what
# origins can cover: the opaque form is the right tool for a hand-laid-out
# block of cells, and the wrong one for a local you stop mentioning.
# expect: Totals dropped
# expect: before parallel_for
# expect: after parallel_for: 499499
from std.memory.alloc import unsafe_alloc
from threads import AtomicCounter, OpaquePtr, opaque_ptr, parallel_for


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


def at(ptr: OpaquePtr) -> ref[MutUntrackedOrigin] Totals:
    return Pointer[Totals, MutUntrackedOrigin](unsafe_from_address=Int(ptr))[]


def task(i: Int, ptr: OpaquePtr) -> None:
    _ = AtomicCounter.at(Int(at(ptr).cell)).fetch_add(Int64(i))


def main() raises:
    var totals = Totals()
    var ptr = opaque_ptr(Int(Pointer(to=totals)))
    print("before parallel_for")
    parallel_for[task](1000, ptr)
    # Not `totals.cell` — a use of `totals` here would move the drop past it.
    print("after parallel_for:", at(ptr).cell[])
