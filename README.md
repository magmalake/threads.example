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

## Comments

The post has no comment box; this repo is where the code can be discussed.
Open an issue, or a pull request against either file.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
