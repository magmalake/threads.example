# threads.example

[![CI](https://github.com/magmalake/threads.example/actions/workflows/ci.yml/badge.svg)](https://github.com/magmalake/threads.example/actions/workflows/ci.yml)

Companion code for [**Writing ergonomic multithreaded code in Mojo 1.0**](https://magmalake.org/blog/writing-multithreaded-code-in-mojo/)
on [magmalake.org](https://magmalake.org).

One file, [`src/main.mojo`](src/main.mojo): the post's whole program, plus the
twenty-line `Ctx[T]` it relies on. It sums `0..1000` from every core through
one shared atomic and prints

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
pixi run run
```

That installs Mojo 1.0.0 and the tin into `.pixi/`, builds `src/main.mojo`,
and runs it. `pixi` itself: <https://pixi.sh>.

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
Open an issue, or a pull request against `src/main.mojo` — reworking it around
origins is the first one on the list.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
