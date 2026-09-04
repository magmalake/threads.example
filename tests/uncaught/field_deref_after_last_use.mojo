# Nothing to do with threads. `totals.cell[]` copies the pointer field, and
# that copy is the struct's last use — so `totals` is destroyed between the
# copy and the deref, and the deref reads the poisoned cell. A method that
# reads through `self` borrows the whole struct for the call and gets the
# right number.
#
# The fix is a type, not a compiler change: `OwnedPointer.__getitem__` returns
# a ref whose origin is the pointer's own, so `owned.cell[]` borrows `owned`
# and it stays alive through the deref. Same shape, right answer, dropped last.
# expect: via method: 499500
# expect: Totals dropped
# expect: via field deref: -1
# expect: via OwnedPointer field deref: 499500
# expect: Owned dropped
# Clean under ThreadSanitizer: this bug is not even concurrent — the drop and
# the deref both happen on the main thread, after `parallel_for` has joined.
# expect-tsan: clean
from std.memory import OwnedPointer
from std.memory.alloc import unsafe_alloc
from threads import AtomicCounter, parallel_for


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

    def sum(self) -> Int64:
        return self.cell[]

    def __deinit__(deinit self):
        print("Totals dropped")
        self.cell[] = -1


struct Owned(Movable):
    """The same struct with the cell behind an `OwnedPointer`.

    Nothing to poison: the deref borrows `self`, so the drop cannot come
    first, and the pointer frees its cell after this destructor runs.
    """

    var cell: OwnedPointer[Int64]

    def __init__(out self):
        self.cell = OwnedPointer(Int64(0))

    def __deinit__(deinit self):
        print("Owned dropped")


def task(i: Int, mut t: Totals) -> None:
    _ = AtomicCounter.at(Int(t.cell)).fetch_add(Int64(i))


def owned_task(i: Int, mut o: Owned) -> None:
    _ = AtomicCounter.at(Int(Pointer(to=o.cell[]))).fetch_add(Int64(i))


def main() raises:
    var totals = Totals()
    parallel_for[task](1000, totals)
    print("via method:", totals.sum())
    print("via field deref:", totals.cell[])

    var owned = Owned()
    parallel_for[owned_task](1000, owned)
    print("via OwnedPointer field deref:", owned.cell[])
