# Building Microkit systems with Zig

This is a basic 'hello world' example for a [seL4 Microkit](https://github.com/seL4/microkit)
system where the [Zig](https://ziglang.org) build system is used to acquire and use the Microkit
SDK. The 'hello world' is still written in C, it is solely the build system that is Zig code.

This example is mainly for my own reference, but may be useful to other interested in the Zig
build system and/or Microkit. The [libvmm](https://github.com/au-ts/libvmm) project has non-trivial
examples of using the Zig build system with Microkit should you be interested.

## Building/running

Dependencies:
* [Zig compiler](https://ziglang.org/download/) (0.12.0-dev.2036+fc79b22a9 or newer)
* QEMU (specifically `qemu-system-aarch64`), for simulating the hello world.

Just like most Zig projects, to build all you need to do is run:
```
zig build
```

You can see all the build options with `zig build -h`.

If you want to run the example you can do:
```sh
zig build qemu
```

