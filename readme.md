# Build

To build run `zig build`. This will create the WASM game file at `zig-out/bin/app.wasm`. Expected version of [Zig](https://ziglang.org) is 0.15.2. For an optimized build run `zig build -Doptimize=ReleaseSmall`. I use watchexec to build on every save with:

```
watchexec -c -w main.zig -- zig build -Doptimize=ReleaseSmall
```

# Open in browser

Due to local cross origin restrictions on WASM files we need to start a web server to run the game locally. Easiest is `python3 -m http.server`, or if that does not work `python -m http.server`. Then you can access the game on `http://localhost:8000/`.
