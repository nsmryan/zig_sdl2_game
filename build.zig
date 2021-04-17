const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("game", "src/main.zig");

    exe.setBuildMode(mode);
    exe.addIncludeDir("deps/layout");
    exe.addLibPath("lib");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");
    exe.linkSystemLibrary("c");

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    const run = b.step("run", "Run the game");
    const run_cmd = exe.run();
    run.dependOn(&run_cmd.step);
}
