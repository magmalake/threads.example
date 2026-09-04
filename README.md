# threads.example

[![CI](https://github.com/magmalake/threads.example/actions/workflows/ci.yml/badge.svg)](https://github.com/magmalake/threads.example/actions/workflows/ci.yml)

Companion code for [**Writing ergonomic multithreaded code in Mojo 1.0**](https://magmalake.org/blog/writing-multithreaded-code-in-mojo/)
on [magmalake.org](https://magmalake.org).

Two files, one program:

- [`src/post.mojo`](src/post.mojo) — the post's whole program, plus the
  twenty-line `Ctx[T]` it relies on, exactly as published.
- [`src/origins.mojo`](src/origins.mojo) — the same program with the origin
  of `totals` kept instead of erased: `parallel_for[task](1000, totals)`
  takes the state by `ref` and the task as `def(Int, mut Totals)`. An
  argument is alive for the whole call, so the compiler extends the lifetime
  of `totals` to cover the joins; a `read` argument or a temporary is a
  compile error. The erasure to `void *` still happens — once, inside
  threads.mojo — because that is all a pthread can carry. An earlier version
  of this file did the same in user code with a `Ctx[T, origin]`, `share` and
  `run`; threads-mojo 0.3.0 moved that into `parallel_for` itself.

Both sum `0..1000` from every core through one shared atomic and print

```
cores: 10  sum: 499500
```

It is built against [threads.mojo](https://github.com/magmalake/threads.mojo)
exactly the way a reader would get it — from [mojoshelf](https://mojoshelf.org),
as a pixi git source dependency — so cloning this repo is also a check that
the install path in the post works.

## Run it

```sh
git clone https://github.com/magmalake/threads.example
cd threads.example
pixi run run        # src/origins.mojo
pixi run run-post   # src/post.mojo
```

That installs Mojo 1.0.0 and the tin into `.pixi/`, builds the program, and
runs it. `pixi` itself: <https://pixi.sh>.

## How the dependency got here

```sh
pixi global install --channel https://mojoshelf.org/channel mojoshelf
pixi shelf add threads-mojo
```

which wrote the `threads-mojo = { git = …, rev = … }` line in
[`pixi.toml`](pixi.toml). magmalake tins are not on a conda channel, so
`pixi add threads-mojo` would find nothing.

## What the compiler catches, and what it does not

`pixi run check` builds six deliberately wrong programs under
[`tests/`](tests/) and holds the compiler to a claim about each one — and then
asks a second question of the four that compile: what does a race detector
make of them?

[`tests/caught/`](tests/caught/) must fail to compile, with the diagnostic the
file names:

| file | misuse | diagnostic |
| --- | --- | --- |
| `state_immutable` | `parallel_for[task](n, x)` with `x` a `read` argument | `cannot be converted from 'Totals' to ref 'Totals'` |
| `state_temporary` | `parallel_for[task](n, Totals(0))` | same |

[`tests/uncaught/`](tests/uncaught/) must compile with no diagnostic at all,
and then print the wrong answer the file predicts:

| file | what goes wrong | output |
| --- | --- | --- |
| `untracked_ctx_drops_early` | the post's `Ctx` erases the origin; `totals` is destroyed at its last visible use, before any thread starts | `Totals dropped` printed first; sum `499499` (−1 + 499500, the tasks adding into the poisoned cell) |
| `opaque_escapes_origin` | the opaque `parallel_for` on `opaque_ptr(Int(Pointer(to=totals)))` — `Int(…)` is where the origin stops, and the boundary of what the typed form covers | same |
| `field_deref_after_last_use` | `totals.cell[]` copies the pointer field, which is the struct's last use, and the deref reads a destroyed object | `-1`; the method read `totals.sum()` gives `499500`, and so does the same field deref once the cell is an `OwnedPointer`, whose deref borrows the struct |
| `plain_store_races` | a task writes `sum` with a plain load and store instead of the atomic — every task holds `mut` access to the same value and nothing says the type is safe to share | lost updates, every run; not a lifetime bug but the one an origin cannot express |

The uncaught set is the list a reviewer has to check by hand. If a newer
compiler starts rejecting one, `check` fails on it — move the file to
`caught/`, record the diagnostic, and the list gets shorter. The destructor in
those tests poisons the cell rather than freeing it, so the misuse stays a
number that can be asserted instead of undefined behaviour.

### And what a sanitizer catches

`check` rebuilds each uncaught case with `mojo build --sanitize thread` and
holds ThreadSanitizer to the verdict the file declares in a
`# expect-tsan: race` or `# expect-tsan: clean` line, next to its `# expect:`
lines. [`src/origins.mojo`](src/origins.mojo) — the corrected listing — carries
the same marker and is the control: a "clean" verdict is only worth reading if
a correct program earns one too.

| file | ThreadSanitizer |
| --- | --- |
| `origins` (the control) | clean |
| `untracked_ctx_drops_early` | clean |
| `opaque_escapes_origin` | clean |
| `field_deref_after_last_use` | clean |
| `plain_store_races` | **data race**, both accesses named |

The three clean verdicts are the finding, not a gap in the harness. Each of
those bugs poisons its cell from the **main** thread — before `pthread_create`
in two cases, after the join in the third — so every access to it is ordered
and there is no race to see. A use-after-destroy is not a data race, and a
race detector is the wrong instrument for one; `L001` and `L002` stay the
things that catch them.

`plain_store_races` is the one that is genuinely concurrent, and it is now
caught twice over: statically by `L003`, and at runtime by a tool that names
the load and the store in `_parallel_worker` and the two threads they ran on.

The leg runs where the sanitizer does. On linux-64 with Mojo 1.0.0 a
`--sanitize thread` binary links and then aborts before `main` — the runtime's
bundled TCMalloc cannot get a 1 GiB-aligned mapping inside the address space
TSan reserved — so a canary decides and `check` prints a skip line rather than
failing. `CHECK_TSAN=1` forces it (to find out whether a newer toolchain has
fixed it); `CHECK_TSAN=0` skips it.

Three of the four are lifetime bugs, and each has a fix that exists today:
pass the state as a `ref` argument (the typed `parallel_for`), keep the
erasure inside the library, and own heap memory through a type whose deref
borrows the owner (`OwnedPointer`, `List`) rather than a raw untracked
`Pointer`. The fourth is a different kind: `parallel_for` gives a thousand
tasks `mut` access to one value, and only an atomic in the task keeps that
honest. Rust would refuse the
aliased `&mut` and let the atomic through on the strength of `Sync`; Mojo has
no such trait yet, so the race is invisible to the compiler and lands in the
uncaught set with the others.

## Comments

The post has no comment box; this repo is where the code can be discussed.
Open an issue, or a pull request against either file.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
