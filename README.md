# threads.example

[![CI](https://github.com/magmalake/threads.example/actions/workflows/ci.yml/badge.svg)](https://github.com/magmalake/threads.example/actions/workflows/ci.yml)

Companion code for [**Writing ergonomic multithreaded code in Mojo 1.0**](https://magmalake.org/blog/writing-multithreaded-code-in-mojo/)
on [magmalake.org](https://magmalake.org).

Two files, one program:

- [`src/post.mojo`](src/post.mojo) — the post's whole program, plus the
  twenty-line `Ctx[T]` it relies on, exactly as published.
- [`src/origins.mojo`](src/origins.mojo) — the same program with the origin
  of `totals` kept in the context type instead of erased. `share(totals)`
  captures it, `run[task](n, ctx)` holds it across the `parallel_for`, and the
  compiler extends the lifetime of `totals` to cover the call. Sharing an
  immutable argument, a temporary, or letting a `Ctx` outlive its state is a
  compile error. The erasure to `void *` still happens — once, inside `run` —
  because that is all a pthread can carry.

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

`pixi run check` builds seven deliberately wrong programs under
[`tests/`](tests/) and holds the compiler to a claim about each one.

[`tests/caught/`](tests/caught/) must fail to compile, with the diagnostic the
file names:

| file | misuse | diagnostic |
| --- | --- | --- |
| `share_immutable` | `share(x)` on a `read` argument | `cannot be converted from 'Totals' to ref 'Totals'` |
| `share_temporary` | `share(Totals(0))` | same |
| `return_ctx_to_local` | `return share(local)` | `cannot implicitly convert 'Ctx[Totals, origin_of(t)]' value to 'Ctx[Totals]'` |
| `ctx_outlives_block` | a `Ctx` assigned in a block, used after it | same |

[`tests/uncaught/`](tests/uncaught/) must compile with no diagnostic at all,
and then print the wrong answer the file predicts:

| file | what goes wrong | output |
| --- | --- | --- |
| `untracked_ctx_drops_early` | the post's `Ctx` erases the origin; `totals` is destroyed at its last visible use, before any thread starts | `Totals dropped` printed first; sum `499499` (−1 + 499500, the tasks adding into the poisoned cell) |
| `opaque_escapes_origin` | `share(totals).opaque()` outside `run` — the boundary of what origins cover | same |
| `field_deref_after_last_use` | `totals.cell[]` copies the pointer field, which is the struct's last use, and the deref reads a destroyed object | `-1`; the method read `totals.sum()` gives `499500` |

The uncaught set is the list a reviewer has to check by hand. If a newer
compiler starts rejecting one, `check` fails on it — move the file to
`caught/`, record the diagnostic, and the list gets shorter. The destructor in
those tests poisons the cell rather than freeing it, so the misuse stays a
number that can be asserted instead of undefined behaviour.

## Comments

The post has no comment box; this repo is where the code can be discussed.
Open an issue, or a pull request against either file.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
