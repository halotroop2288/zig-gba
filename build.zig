const std = @import("std");
const builtin = @import("builtin");

const title = "zig-gba";
const emulator = "mgba";
const flags = .{"-lgba"};
const devkitpro = "/opt/devkitpro";
const devkitarm = devkitpro ++ "/devkitARM";

const include_paths = [_][]const u8{
    devkitarm ++ "/arm-none-eabi/include",
    devkitarm ++ "/lib/gcc/arm-none-eabi/16.1.0/include",
    devkitarm ++ "/lib/gcc/arm-none-eabi/16.1.0/include-fixed",
    devkitpro ++ "/libgba/include",
    devkitpro ++ "/portlibs/gba/include",
    devkitpro ++ "/portlibs/armv4/include",
};

pub fn build(b: *std.Build) void {
    b.libc_file = "libc.txt";

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm7tdmi },
    });
    const optimize = b.standardOptimizeOption(.{});

    const c_imports = b.addTranslateC(.{
        .root_source_file = b.path("src/gba/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (include_paths) |path| {
        c_imports.addIncludePath(.{ .cwd_relative = path });
    }

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("gba", c_imports.createModule());

    const obj = b.addObject(.{
        .name = title,
        .root_module = mod,
    });

    const extension = if (builtin.target.os.tag == .windows) ".exe" else "";
    const elf = b.addSystemCommand(&.{
        devkitpro ++ "/devkitARM/bin/arm-none-eabi-gcc" ++ extension,
        "-g",
        "-mthumb",
        "-mthumb-interwork",
    });
    _ = elf.addPrefixedOutputFileArg("-Wl,-Map,", title ++ ".map");
    elf.addPrefixedFileArg("-specs=", std.Build.LazyPath{ .cwd_relative = devkitpro ++ "/devkitARM/arm-none-eabi/lib/gba.specs" });
    elf.addFileArg(obj.getEmittedBin());
    elf.addArgs(&.{
        "-L" ++ devkitpro ++ "/libgba/lib",
        "-L" ++ devkitpro ++ "/portlibs/gba/lib",
        "-L" ++ devkitpro ++ "/portlibs/armv4/lib",
    });
    elf.addArgs(&flags);
    elf.addArg("-o");
    const elf_file = elf.addOutputFileArg(title ++ ".elf");

    const gba = b.addSystemCommand(&.{
        devkitpro ++ "/devkitARM/bin/arm-none-eabi-objcopy" ++ extension,
        "-O",
        "binary",
    });
    gba.addFileArg(elf_file);
    const gba_file = gba.addOutputFileArg(title ++ ".gba");

    const fix = b.addSystemCommand(&.{devkitpro ++ "/tools/bin/gbafix" ++ extension});
    fix.addFileArg(gba_file);

    const install = b.addInstallBinFile(gba_file, title ++ ".gba");

    b.default_step.dependOn(&install.step);
    install.step.dependOn(&fix.step);
    fix.step.dependOn(&gba.step);
    gba.step.dependOn(&elf.step);
    elf.step.dependOn(&obj.step);

    const run_step = b.step("run", "Run in mGBA");
    const mgba = b.addSystemCommand(&.{emulator});
    mgba.addFileArg(gba_file);
    run_step.dependOn(&install.step);
    run_step.dependOn(&mgba.step);
}
