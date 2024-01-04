const std = @import("std");
const builtin = @import("builtin");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    // For simplicity we hard-code the target to be the QEMU ARM virt platform.
    // This could obviously be extended by say having an array of Zig targets
    // and having a build option to select one of them.
    const target_query = std.Target.Query{
        .cpu_arch = .aarch64,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
        .os_tag = .freestanding,
        .abi = .none,
    };
    const resolved_target = b.resolveTargetQuery(target_query);

    // Microkit name for our target, the QEMU ARM virt platform
    const board = "qemu_arm_virt";
    const config = "debug";

    // Depending on the host, we need a different Microkit SDK. Right now
    // only Linux x64 and macOS x64/ARM64 are supported, so we need to check
    // what platform the person compiling the project is using.
    const microkit_sdk_name = switch (builtin.target.os.tag) {
        .linux => switch (builtin.target.cpu.arch) {
            .x86_64 => "microkit_linux_x64",
            else => {
                std.debug.print("ERROR: only x64 is supported on Linux.", .{});
                std.os.exit(1);
            }
        },
        .macos => switch (builtin.target.cpu.arch) {
            .x86_64 => "microkit_macos_x64",
            .aarch64 => "microkit_macos_arm64",
            else => {
                std.debug.print("ERROR: only x64 and ARM64 are supported on macOS.", .{});
                std.os.exit(1);
            }
        },
        else => {
            std.debug.print("ERROR: OS '{s}' is not supported.", .{ builtin.target.os.tag });
        }
    };
    // Declare our dependency on the Microkit SDK that is outlined in the 'build.zig.zon' file.
    const microkit = b.dependency(microkit_sdk_name, .{});

    const microkit_board_dir = "board/" ++ board ++ "/" ++ config;
    const libmicrokit = microkit.path(microkit_board_dir ++ "/lib/libmicrokit.a");
    const libmicrokit_linker_script = microkit.path(microkit_board_dir ++ "/lib/microkit.ld");
    const libmicrokit_include = microkit.path(microkit_board_dir ++ "/include");

    // Create a build step for our hello world program
    const exe = b.addExecutable(.{
        .name = "hello.elf",
        .target = resolved_target,
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

    const microkit_tool = microkit.path("bin/microkit").getPath(b);
    // Until https://github.com/ziglang/zig/issues/17462 is solved, the Zig build
    // system does not respect the executable mode of dependencies, this affects
    // using the Microkit SDK since the tool is expected to be executable.
    // For now, we manually make it executable ourselves.
    const microkit_tool_chmod = b.addSystemCommand(&[_][]const u8{ "chmod", "+x", microkit_tool });

    // Setup the defualt build step which will take our hello world ELF and build the final system
    // image using the Microkit tool.
    const microkit_tool_cmd = b.addSystemCommand(&[_][]const u8{
       microkit_tool,
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
    const loader_arg = std.fmt.allocPrint(gpa, "loader,file={s},addr=0x70000000,cpu-num=0", .{ system_image })
                       catch "Could not format print!";
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
