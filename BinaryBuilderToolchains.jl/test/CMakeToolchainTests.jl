using Test, BinaryBuilderToolchains
using BinaryBuilderToolchains: path_appending_merge

# testsuite outputs go here:
ENV["TESTSUITE_OUTPUT_DIR"] = mktempdir()

@testset "cmake wrapper" begin
    using BinaryBuilderToolchains: cmake_wrapper, compiler_wrapper
    mktempdir() do dir
        # A stand-in for `cmake` that prints the arguments it gets, one per line
        fake_cmake = joinpath(dir, "fake-cmake")
        write(fake_cmake, "#!/bin/bash\nprintf '%s\\n' \"\$@\"\n")
        chmod(fake_cmake, 0o755)
        wrapper = joinpath(dir, "cmake")
        compiler_wrapper(io -> cmake_wrapper(io, "/opt/toolchain.cmake"), wrapper, fake_cmake)
        cmake_args(args...) = split(readchomp(`$(wrapper) $(args)`), "\n")
        tc = "-DCMAKE_TOOLCHAIN_FILE=/opt/toolchain.cmake"

        # Configuring a project gets our toolchain file
        @test cmake_args("-S", "src", "-B", "build") == [tc, "-S", "src", "-B", "build"]
        @test cmake_args("--preset", "default") == [tc, "--preset", "default"]
        # unless it is given one of its own
        for user_tc in (["-DCMAKE_TOOLCHAIN_FILE=/mine.cmake"], ["-D", "CMAKE_TOOLCHAIN_FILE:FILEPATH=/mine.cmake"])
            @test cmake_args("-S", "src", user_tc...) == ["-S", "src", user_tc...]
        end

        # The modes that must come first, and scripts, are left alone
        for args in (["--build", "build", "--parallel", "2"],
                     ["--install", "build", "--prefix", "/opt/prefix"],
                     ["--open", "build"],
                     ["--workflow", "--preset", "default"],
                     ["-E", "echo", "hello world"],
                     ["-P", "script.cmake"],
                     ["-DFOO=1", "-P", "script.cmake"])
            @test cmake_args(args...) == args
        end
        # Arguments that merely contain those flags do not count
        @test cmake_args("-S", "src", "-DFOO=--build", "-DBAR=-E") == [tc, "-S", "src", "-DFOO=--build", "-DBAR=-E"]
        @test cmake_args("-DFOO=-P", "-S", "src") == [tc, "-DFOO=-P", "-S", "src"]
    end
end

@testset "CMakeToolchain" begin
    platform = CrossPlatform(BBHostPlatform() => BBHostPlatform())
    toolchains = [
        CToolchain(platform),
        HostToolsToolchain(platform),
        CMakeToolchain(platform),
    ]
    # First, simple toolchain tests
    with_toolchains(toolchains) do prefix, env
        toolchain_tests(prefix, env, platform, "CMakeToolchain")

        # Configure, build and install a project, and run a command and a script, all
        # through the `cmake` wrapper: only configuring gets our toolchain file.
        @testset "cmake modes" begin
            mktempdir() do dir
                src_dir = joinpath(dir, "src")
                mkpath(src_dir)
                cp(joinpath(@__DIR__, "testsuite", "CMakeToolchain", "00_hello_world", "hello.c"), joinpath(src_dir, "hello.c"); follow_symlinks=true)
                write(joinpath(src_dir, "CMakeLists.txt"), """
                cmake_minimum_required(VERSION 3.13)
                project(cmake_modes C)
                add_executable(hello hello.c)
                install(TARGETS hello)
                """)
                write(joinpath(dir, "script.cmake"), "message(\"toolchain file: [\${CMAKE_TOOLCHAIN_FILE}]\")\n")
                build_dir = joinpath(dir, "build")
                install_dir = joinpath(dir, "install")
                function run_cmake(args...)
                    p, output = capture_output(setenv(Cmd(["/bin/bash", "-c", "\$CMAKE \"\$@\"", "cmake", args...]), env))
                    if !success(p)
                        println(output)
                    end
                    @test success(p)
                    return strip(output)
                end

                run_cmake("-S", src_dir, "-B", build_dir)
                cmake_cache = read(joinpath(build_dir, "CMakeCache.txt"), String)
                @test occursin(r"^CMAKE_TOOLCHAIN_FILE:[A-Z]+=.*/wrappers/toolchain\.cmake$"m, cmake_cache)
                run_cmake("--build", build_dir)
                @test isfile(joinpath(build_dir, "hello"))
                run_cmake("--install", build_dir, "--prefix", install_dir)
                @test isfile(joinpath(install_dir, "bin", "hello"))
                @test run_cmake("-E", "echo", "hello world") == "hello world"
                @test run_cmake("-P", joinpath(dir, "script.cmake")) == "toolchain file: []"
            end
        end
    end

    # Next, test that we can hook up multiple `CMakeToolchain`s
    # with their respective `CToolchain`'s, we'll switch the c++ string ABI
    # version between our "host" and "target" toolchains:
    function BBHostPlatformCxxTag(cxx11::Bool)
        p = BBHostPlatform()
        p["cxxstring_abi"] = cxx11 ? "cxx11" : "cxx03"
        return p
    end
    host_platform = CrossPlatform(BBHostPlatform() => BBHostPlatformCxxTag(false))
    host_ctoolchain = CToolchain(
        host_platform;
        env_prefixes=["HOST_"],
        wrapper_prefixes=["host-"],
        use_ccache=false,
    )
    host_cmaketoolchain = CMakeToolchain(host_platform;
        env_prefixes=["HOST_"],
        wrapper_prefixes=["host-"],
    )

    target_platform = CrossPlatform(BBHostPlatform() => BBHostPlatformCxxTag(true))
    target_ctoolchain = CToolchain(
        target_platform;
        use_ccache=false,
    )
    target_cmaketoolchain = CMakeToolchain(target_platform)

    # Deploy host to one directory, target to another:
    host_toolchains = [
        host_ctoolchain,
        host_cmaketoolchain,
        HostToolsToolchain(host_platform),
    ]
    target_toolchains = [
        target_ctoolchain,
        target_cmaketoolchain,
    ]
    function build_check_compiler(project_dir, cmake_var, cxx11, env)
        env["BB_WRAPPERS_VERBOSE"]="true"
        mktempdir() do build_dir
            p, output = capture_output(setenv(`bash -c "\$$(cmake_var) -B$(build_dir) -S$(project_dir)"`, env))
            if !success(p)
                @error("\$$(cmake_var) failed:")
                println(output)
            end
            @test success(p)
            @test occursin("-D_GLIBCXX_USE_CXX11_ABI=$(cxx11 ? "1" : "0")", output)
        end
    end
    hello_world_path = joinpath(@__DIR__, "testsuite", "CMakeToolchain", "00_hello_world")
    with_toolchains(host_toolchains) do host_prefix, host_env
        with_toolchains(target_toolchains) do target_prefix, target_env
            env = path_appending_merge(host_env, target_env)
            # Ensure that each `cmake` invokes a different compiler:
            build_check_compiler(hello_world_path, "CMAKE", true, env)
            build_check_compiler(hello_world_path, "HOST_CMAKE", false, env)
        end
    end

    # Next, ensure that we can compile all tests on all platforms
    @info("Running cmake tests for $(length(supported_platforms(CToolchain))) platforms")
    for target in supported_platforms(CMakeToolchain)
        target_platform = CrossPlatform(BBHostPlatform() => target)
        for vendor in vendors_to_test()
            c_toolchain = CToolchain(target_platform; vendor, use_ccache=false)
            cmake_toolchain = CMakeToolchain(target_platform)
            hosttools_toolchain = HostToolsToolchain(target_platform)
            with_toolchains([c_toolchain, cmake_toolchain, hosttools_toolchain]) do prefix, env
                @testset "$(triplet(target)) - $(vendor)" begin
                    # First, run `$CMAKE --version`
                    p, output = capture_output(setenv(`bash -c "\$CMAKE --version"`, env))
                    if !success(p)
                        println(output)
                    end
                    @test success(p)

                    # Next, run `make compile-all`
                    cd(joinpath(@__DIR__, "testsuite", "CMakeToolchain")) do
                        p, output = capture_output(setenv(Cmd(["/bin/bash", "-c", "make clean-all && make compile-all"]), env))
                        if !success(p)
                            println(output)
                        end
                        @test success(p)
                    end
                end
            end
        end
    end
end
