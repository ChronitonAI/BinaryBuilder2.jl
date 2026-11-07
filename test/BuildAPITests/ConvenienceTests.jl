
using Test, BinaryBuilder2, Random
using BinaryBuilder2: get_package_result, JLLPackageDependencies, PackageSpec

if !isdefined(@__MODULE__, :TestingUtils)
    include(joinpath(pkgdir(BinaryBuilder2), "test", "TestingUtils.jl"))
end

@testset "build_tarballs()" begin
    # Create a meta with a universe that we will then inspect as other
    # builds register things into it.
    universe_name = "BB2_tests-$(randstring(4))"
    meta = BuildMeta(;universe_name,target_list=[BBHostPlatform()])
    bootstrap_dir = joinpath(pkgdir(BinaryBuilder2), "bootstrap")

    @testset "Zlib" begin
        # Test a `--dry-run` first!
        zlib_build_script_path = joinpath(bootstrap_dir, "Zlib", "build_tarballs.jl")
        run_build_tarballs(meta, zlib_build_script_path; dry_run=true)
        @test length(meta.packagings) > 0
        @test all(result.status == :skipped for result in values(meta.builds))
        @test all(result.status == :skipped for result in values(meta.extractions))
        @test all(result.status == :skipped for result in values(meta.packagings))
        @test all(config.src_name == "Zlib" for config in keys(meta.builds))

        # Test that we can take that dry run output and get everything we need for a `build_tarballs()` invocation
        build_args = extract_build_tarballs(get_package_result(meta, "Zlib"))
        empty!(meta.packagings)
        build_tarballs(;build_args..., build_script_path = zlib_build_script_path)
        package_result = get_package_result(meta, "Zlib")
        @test package_result.status == :success

        # Next, test some failing builds
        fail_build_args = copy(build_args)
        fail_build_args[:script] = "false"
        @test_throws BuildError build_tarballs(;fail_build_args...)
        fail_extract_args = copy(build_args)
        fail_extract_args[:extract_script] = "false"
        @test_throws BuildError build_tarballs(;fail_extract_args...)
    end
    @testset "Ncurses" begin
        run_build_tarballs(meta, joinpath(bootstrap_dir, "Ncurses", "build_tarballs.jl"))
        @test get_package_result(meta, "Ncurses").status == :success
    end
    @testset "Readline" begin
        run_build_tarballs(meta, joinpath(bootstrap_dir, "Readline", "build_tarballs.jl"))
        @test get_package_result(meta, "Readline").status == :success
    end

    # Test that we can see these builds in our universe:
    uni = Universe(universe_name; persistent=false)
    jll_names = ["Zlib_jll", "Ncurses_jll", "Readline_jll"]
    @test all(BinaryBuilder2.contains_jll.((uni,), jll_names))

    # Test that these builds got the correct build_script_path
    function check_build_script_path(name)
        true_path = abspath(joinpath(bootstrap_dir, name, "build_tarballs.jl"))
        for build_result in collect_builds(meta[name])
            @test abspath(build_result.config.build_script_path) == true_path
        end
    end
    check_build_script_path("Zlib")
    check_build_script_path("Readline")
    check_build_script_path("Ncurses")

    # All the tests above target a native linux; let's run a test on Windows and macOS, just so that
    # we're exercising those troublesome platforms in at least some way:
    @testset "Zlib on Windows and macOS" begin
        meta = BuildMeta(;universe_name,target_list=[Platform("x86_64", "windows"), Platform("aarch64", "macos"; os_version=v"20")])
        run_build_tarballs(meta, joinpath(bootstrap_dir, "Zlib", "build_tarballs.jl"))
        package_result = get_package_result(meta, "Zlib")
        @test package_result.status == :success
    end

    @testset "Multi-stage build test (high-level)" begin
        meta = BuildMeta(;universe_name)
        run_build_tarballs(meta, joinpath(@__DIR__, "build_examples", "multi_stage_build.jl"))

        for package_name in ("libstring", "libstring_headers", "cxx_string_abi")
            package_result = get_package_result(meta, package_name)
            @test package_result.status == :success
        end
    end

    @testset "BinaryBuilder2.Compat" begin
        meta = BuildMeta(;dry_run=["build"])
        run_build_tarballs(meta, joinpath(@__DIR__, "build_examples", "binary_builder_one.jl"))
        @test meta["SSW"].status == :skipped

        # Ensure that `compilers` gets mapped to the appropriate toolchains
        target_toolchains, host_toolchains = BinaryBuilder2.Compat.compilers_to_toolchains([:c])
        @test any(isa.(target_toolchains, PlatformlessWrapper{CToolchain}))
        @test any(isa.(target_toolchains, PlatformlessWrapper{CMakeToolchain}))
        @test any(isa.(host_toolchains, PlatformlessWrapper{CToolchain}))
        @test any(isa.(host_toolchains, PlatformlessWrapper{HostToolsToolchain}))
        @test_throws ArgumentError BinaryBuilder2.Compat.compilers_to_toolchains([:c, :rust])
        @test !any(isa.(target_toolchains, PlatformlessWrapper{FortranToolchain}))

        # Recipes opt into Fortran with `:fortran`
        target_toolchains, host_toolchains = BinaryBuilder2.Compat.compilers_to_toolchains([:c, :fortran])
        @test any(isa.(target_toolchains, PlatformlessWrapper{CToolchain}))
        @test any(isa.(target_toolchains, PlatformlessWrapper{FortranToolchain}))
        @test any(isa.(host_toolchains, PlatformlessWrapper{FortranToolchain}))

        # BinaryBuilder1's `lock_microarchitecture`, for the C and Fortran toolchains of both
        locked(tcs) = [tc.kwargs[:lock_microarchitecture] for tc in tcs
                       if isa(tc, Union{PlatformlessWrapper{CToolchain},PlatformlessWrapper{FortranToolchain}})]
        target_toolchains, host_toolchains = BinaryBuilder2.Compat.compilers_to_toolchains([:c, :fortran])
        @test locked(target_toolchains) == [true, true]
        @test locked(host_toolchains) == [true, true]
        target_toolchains, host_toolchains = BinaryBuilder2.Compat.compilers_to_toolchains([:c, :fortran]; lock_microarchitecture=false)
        @test locked(target_toolchains) == [false, false]
        @test locked(host_toolchains) == [false, false]
        native_linux = Platform(arch(HostPlatform()), "linux")
        for (pw, lock) in ((only(filter(t -> isa(t, PlatformlessWrapper{CToolchain}), target_toolchains)), false),
                           (only(filter(t -> isa(t, PlatformlessWrapper{FortranToolchain}), target_toolchains)), false))
            @test BinaryBuilder2.apply_platform(pw, CrossPlatform(native_linux => native_linux)).lock_microarchitecture == lock
        end
    end

    @testset "FortranToolchain" begin
        native_linux = Platform(arch(HostPlatform()), "linux")
        spec_plan = make_target_spec_plan(;
            host_toolchains = [CToolchain(), FortranToolchain(), HostToolsToolchain()],
            target_toolchains = [CToolchain(), FortranToolchain()],
        )
        target_specs = apply_spec_plan(spec_plan, native_linux, native_linux)
        config = BuildConfig(BuildMeta(; dry_run=["build"]), "fortran", v"1.0.0", [], target_specs, "true")
        for bts in target_specs
            ct = only(filter(t -> isa(t, CToolchain), bts.toolchains))
            ft = only(filter(t -> isa(t, FortranToolchain), bts.toolchains))
            # Its flags point at the spec's install prefix, whose `include` holds modules too
            prefix = BinaryBuilder2.target_prefix(bts)
            @test ft.extra_fflags == ["-I$(prefix)/include"]
            @test ft.extra_ldflags == ["-L$(prefix)/lib"]
            # Its wrappers and variables are named like the C compilers
            @test ft.wrapper_prefixes == ct.wrapper_prefixes
            @test ft.env_prefixes == ct.env_prefixes
            # It shares the C toolchain's GCC: each JLL is installed once
            jlls = [src for src in config.source_trees[BinaryBuilder2.toolchain_prefix(bts, ft)] if isa(src, JLLSource)]
            @test allunique([jll.package.name for jll in jlls])
            @test any(jll -> jll.package.name == "GCC_jll", jlls)

            @test BinaryBuilder2.apply_platform(ft, bts.platform) === ft
            @test isa(PlatformlessWrapper(ft), PlatformlessWrapper{FortranToolchain})
        end
        gfortran(prefix) = string(prefix, triplet(native_linux), "-gfortran")
        for var in ("FC", "TARGETFC", "TARGET_FC")
            @test config.env[var] == gfortran("target-")
        end
        for var in ("HOSTFC", "HOST_FC")
            @test config.env[var] == gfortran("host-")
        end
    end

    @testset "host and build deps" begin
        meta = BuildMeta(;dry_run=["build"])
        build_tarballs(;
            meta,
            src_name = "libcxxstring",
            src_version = v"1.2.3",
            sources = [cxx_string_abi_source],
            script = "true",
            target_dependencies = [JLLSource("Zlib_jll")],
            target_build_time_dependencies = [JLLSource("LinuxKernelHeaders_jll")],
            host_dependencies = [JLLSource("GNUMake_jll")],
        )

        # Ensure that each spec has the correct dependencies recorded
        for build in collect_builds(meta["libcxxstring"])
            for spec in build.config.target_specs
                if spec.name == "host"
                    @test only(spec.dependencies).package.name == "GNUMake_jll"
                elseif spec.name == "target"
                    @test only(spec.dependencies).package.name == "Zlib_jll"
                    @test only(spec.build_time_dependencies).package.name == "LinuxKernelHeaders_jll"
                end
            end
        end

        # Test that only Zlib_jll is recorded as a dependency
        for extraction in collect_extractions(meta["libcxxstring"])
            @test only(JLLPackageDependencies(extraction, PackageSpec[])).name == :Zlib_jll
        end
    end
end
