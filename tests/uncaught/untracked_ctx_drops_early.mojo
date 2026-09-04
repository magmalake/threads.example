# The post's `Ctx` erases the origin, so the compiler destroys `totals` at its
# last visible use — `Ctx.to(totals)` — before a single thread has started.
# Compiles with no diagnostic. Expected here: the drop printed FIRST, and the
# thousand additions landing on the poisoned cell: -1 + 499500.
# expect: Totals dropped
# expect: before parallel_for
# expect: after parallel_for: 499499
# Clean under ThreadSanitizer, and that is the point rather than a gap: the
# poisoning write happens on the main thread *before* `pthread_create`, so it
# is ordered against every task's read of the cell and there is no race to
# report. A use-after-destroy is not a race; mojolint's L001 is what catches
# this one.
# expect-tsan: clean
from std.memory.alloc import unsafe_alloc
from threads import AtomicCounter, OpaquePtr, parallel_for


@fieldwise_init
struct Ctx[T: AnyType](Copyable, Movable):
    var _ptr: Pointer[Self.T, MutUntrackedOrigin]

    @staticmethod
    def to(ref state: Self.T) -> Self:
        return Self(
            Pointer[Self.T, MutUntrackedOrigin](
                unsafe_from_address=Int(Pointer(to=state))
            )
        )

    @staticmethod
    def of(ptr: OpaquePtr) -> Self:
        return Self(
            Pointer[Self.T, MutUntrackedOrigin](unsafe_from_address=Int(ptr))
        )

    def __getitem__(self) -> ref[MutUntrackedOrigin] Self.T:
        return self._ptr[]

    def opaque(self) -> OpaquePtr:
        return OpaquePtr(unsafe_from_address=Int(self._ptr))


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
    var ctx = Ctx[Totals].to(totals).opaque()
    print("before parallel_for")
    parallel_for[task](1000, ctx)
    # Not `totals.cell` — a use of `totals` here would move the drop past it.
    print("after parallel_for:", Ctx[Totals].of(ctx)[].cell[])
