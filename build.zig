const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    // For simplicity we hard-code the target to be the QEMU ARM virt platform.
    // This could obviously be extended by say having an array of Zig targets
    // and having a build option to select one of them.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
        .os_tag = .freestanding,
        .abi = .none,
    });

    // Microkit name for our target, the QEMU ARM virt platform
    const board = "qemu_virt_aarch64";
    const config = "debug";

    // Depending on the host, we need a different Microkit SDK. Right now
    // only Linux x64 and macOS x64/ARM64 are supported, so we need to check
    // what platform the person compiling the project is using.
    const microkit_dep = switch (builtin.target.os.tag) {
        .linux => switch (builtin.target.cpu.arch) {
            .x86_64 => b.lazyDependency("microkit_linux_x86_64", .{}),
            else => {
                std.debug.print("ERROR: only x64 is supported on Linux.", .{});
                std.os.exit(1);
            }
        },
        .macos => switch (builtin.target.cpu.arch) {
            .x86_64 => b.lazyDependency("microkit_macos_x86_64", .{}),
            .aarch64 => b.lazyDependency("microkit_macos_aarch64", .{}),
            else => {
                std.debug.print("ERROR: only x64 and ARM64 are supported on macOS.", .{});
                std.os.exit(1);
            }
        },
        else => {
            std.debug.print("ERROR: building on OS '{s}' is not supported.", .{ builtin.target.os.tag });
        }
    };

    // The following logic is necessary because we are using 'lazy' dependencies. Because
    // there are different SDKs for each host OS/architecture, we specify all of them in
    // our build.zig.zon and declare them as 'lazy'. This causes Zig to check what SDK
    // actually ends up getting used (it will only be one in our case) and hence only
    // fetches that SDK. That way, when you do `zig build` it will only download the
    // SDK that you actually need, rather than all of them.
    if (microkit_dep) |microkit| {
        const microkit_board_dir = "board/" ++ board ++ "/" ++ config;
        const libmicrokit = microkit.path(microkit_board_dir ++ "/lib/libmicrokit.a");
        const libmicrokit_linker_script = microkit.path(microkit_board_dir ++ "/lib/microkit.ld");
        const libmicrokit_include = microkit.path(microkit_board_dir ++ "/include");

        // Create a build step for our hello world program
        const exe = b.addExecutable(.{
            .name = "hello.elf",
            .target = target,
            .optimize = optimize,
        });
        exe.addCSourceFiles(.{ .files = &.{ "hello.c" }});
        exe.addObjectFile(libmicrokit);
        exe.setLinkerScriptPath(libmicrokit_linker_script);
        exe.addIncludePath(libmicrokit_include);
        // Install the ELF in the chosen build directory (defaults to ./zig-out/bin)
        b.installArtifact(exe);

        const sdf = "hello.system";
        const system_image = b.getInstallPath(.bin, "./loader.img");

        const microkit_tool = microkit.path("bin/microkit");
        // Until https://github.com/ziglang/zig/issues/17462 is solved, the Zig build
        // system does not respect the executable mode of dependencies, this affects
        // using the Microkit SDK since the tool is expected to be executable.
        // For now, we manually make it executable ourselves.
        const microkit_tool_chmod = b.addSystemCommand(&[_][]const u8{ "chmod", "+x" });
        microkit_tool_chmod.addFileArg(microkit_tool);

        // Setup the defualt build step which will take our hello world ELF and build the final system
        // image using the Microkit tool.
        const microkit_tool_cmd = std.Build.Step.Run.create(b, "run ");
        microkit_tool_cmd.addFileArg(microkit_tool);
        microkit_tool_cmd.addArgs(&[_][]const u8{
           sdf,
           "--search-path",
           b.getInstallPath(.bin, ""),
           "--board",
           board,
           "--config",
           config,
           "-o",
           system_image,
           "-r",
           b.getInstallPath(.prefix, "./report.txt")
        });
        microkit_tool_cmd.step.dependOn(&microkit_tool_chmod.step);
        microkit_tool_cmd.step.dependOn(b.getInstallStep());
        const microkit_step = b.step("microkit", "Compile and build the bootable system image");
        microkit_step.dependOn(&microkit_tool_cmd.step);
        b.default_step = microkit_step;

        // This is setting up a `qemu` command for running the system image via QEMU.
        const loader_arg = b.fmt("loader,file={s},addr=0x70000000,cpu-num=0", .{ system_image });
        const qemu_cmd = b.addSystemCommand(&[_][]const u8{
            "qemu-system-aarch64",
            "-machine",
            "virt,virtualization=on,highmem=off,secure=off",
            "-cpu",
            "cortex-a53",
            "-serial",
            "mon:stdio",
            "-device",
            loader_arg,
            "-m",
            "2G",
            "-nographic",
        });
        qemu_cmd.step.dependOn(b.default_step);
        const simulate_step = b.step("qemu", "Simulate the system via QEMU");
        simulate_step.dependOn(&qemu_cmd.step);
    }
}
