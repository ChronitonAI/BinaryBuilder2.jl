using Test, BinaryBuilderSources, BinaryBuilderToolchains, BinaryBuilderPlatformExtensions, Base.BinaryPlatforms
using BinaryBuilderToolchains: path_appending_merge, gfortran_wrappers, get_vendor

# testsuite outputs go here:
ENV["TESTSUITE_OUTPUT_DIR"] = mktempdir()

# What identifies a JLL within a prefix (see `deduplicate_jlls()`), and what it requests
jll_key(jll) = (jll.package.name, jll.target, triplet(jll.platform))
jll_request(jll) = (jll_key(jll)..., jll.package.repo.source, jll.package.repo.rev, jll.package.version)

# The JLLs of a `CToolchain`, its binutils included
ctoolchain_jlls(ct) = JLLSource[ct.binutils_toolchain.deps..., ct.deps...]

@testset "FortranToolchain" begin
    native = CrossPlatform(BBHostPlatform() => HostPlatform())
    native_triplet = triplet(gcc_platform(native.target))

    @testset "construction" begin
        # GCC is the vendor everywhere, also where the C toolchain defaults to clang
        for target in (HostPlatform(), Platform("aarch64", "macos"), Platform("x86_64", "freebsd"))
            ft = FortranToolchain(CrossPlatform(BBHostPlatform() => target))
            @test ft.vendor == :gcc
            @test get_vendor(ft) == :gcc
            @test any(jll -> jll.package.name == "GCC_jll", ft.deps)
        end
        @test FortranToolchain(native; vendor=:bootstrap).vendor == :gcc_bootstrap
        @test FortranToolchain(native; vendor=:gcc_bootstrap).vendor == :gcc_bootstrap
        @test any(jll -> jll.package.name == "GCCBootstrap_jll", FortranToolchain(native; vendor=:gcc_bootstrap).deps)
        for vendor in (:clang, :clang_bootstrap, :ifort)
            @test_throws ArgumentError FortranToolchain(native; vendor)
        end
        @test_throws ArgumentError FortranToolchain(native; wrapper_prefixes=String[])
        @test_throws ArgumentError FortranToolchain(native; env_prefixes=String[])

        # GCC 14 only builds against libgfortran5
        for (version, ok) in (("3.0.0", false), ("4.0.0", false), ("5.0.0", true))
            target = Platform(arch(HostPlatform()), "linux"; libgfortran_version=version)
            cp = CrossPlatform(BBHostPlatform() => target)
            if ok
                @test FortranToolchain(cp).gcc_version == v"14.2.0"
            else
                @test_throws ArgumentError FortranToolchain(cp)
            end
        end
    end

    @testset "expand_gfortran_versions" begin
        p = Platform("x86_64", "linux")
        @test expand_gfortran_versions(p) == [Platform("x86_64", "linux"; libgfortran_version="5.0.0")]
        @test expand_gfortran_versions([p, Platform("aarch64", "macos")]) == [
            Platform("x86_64", "linux"; libgfortran_version="5.0.0"),
            Platform("aarch64", "macos"; libgfortran_version="5.0.0"),
        ]
        # Already tagged, or not using libgfortran
        tagged = Platform("x86_64", "linux"; libgfortran_version="4.0.0")
        @test expand_gfortran_versions(tagged) == [tagged]
        @test expand_gfortran_versions(AnyPlatform()) == [AnyPlatform()]
        msan = Platform("x86_64", "linux"; sanitize="memory")
        @test expand_gfortran_versions(msan) == [msan]
        @test_throws ArgumentError expand_gfortran_versions(p; old_abis=true)
    end

    # The GCC that a `FortranToolchain` installs is the one of the `CToolchain` next to it,
    # down to the JLL requests, so that the two merge in a prefix
    @testset "JLLs shared with the CToolchain" begin
        for target in (HostPlatform(),
                       Platform("aarch64", "linux"), Platform("x86_64", "windows"),
                       Platform("aarch64", "macos"), Platform("x86_64", "linux"; libc="musl"))
            cp = CrossPlatform(BBHostPlatform() => target)
            for vendor in (:gcc, :gcc_bootstrap)
                ct = CToolchain(cp; vendor, use_ccache=false)
                ft = FortranToolchain(cp; vendor)
                @test Set(jll_request.(ft.deps)) == Set(jll_request.(ctoolchain_jlls(ct)))
                merged = deduplicate_jlls(JLLSource[ctoolchain_jlls(ct)..., ft.deps...])
                @test jll_key.(merged) == jll_key.(ctoolchain_jlls(ct))
            end

            # Next to clang it brings its own GCC, with its own sysroot, in its own directory
            if Sys.isapple(target)
                ct = CToolchain(cp; vendor=:clang)
                ft = FortranToolchain(cp)
                for name in ("GCC_jll", "GCC_support_libraries_jll", "macOSSDK_jll")
                    @test startswith(only(filter(jll -> jll.package.name == name, ft.deps)).target, "gcc")
                end
                merged = deduplicate_jlls(JLLSource[ctoolchain_jlls(ct)..., ft.deps...])
                @test count(jll -> jll.package.name == "macOSSDK_jll", merged) == 2
                @test count(jll -> jll.package.name == "GCC_jll", merged) == 1
            end
        end
    end

    @testset "wrappers" begin
        let target = HostPlatform()
            cp = CrossPlatform(BBHostPlatform() => target)
            ft = FortranToolchain(cp;
                env_prefixes=["HOST", "HOST_", ""],
                wrapper_prefixes=["host-\${triplet}-", "\${triplet}-", ""],
                extra_fflags=["-I/prefix/include"],
                extra_ldflags=["-L/prefix/lib"],
            )
            t = triplet(gcc_platform(target))
            mktempdir() do dir
                gfortran_wrappers(ft, dir)
                @test sort(readdir(dir)) == sort(vec([string(p, tool) for p in ("host-$(t)-", "$(t)-", ""), tool in ("gfortran", "f77")]))
                script = read(joinpath(dir, "$(t)-gfortran"), String)
                @test occursin("bin/$(t)-gfortran", script)
                @test read(joinpath(dir, "f77"), String) == script
                # The flags of the C toolchain's gcc wrappers ...
                @test occursin("Cannot force an architecture via -march", script)
                @test occursin("\"-march=", script)
                @test occursin("\"-I/prefix/include\"", script)
                @test occursin("\"-L/prefix/lib\"", script)
                @test occursin("-Wl,-rpath-link,", script)
                @test occursin("-frandom-seed=", script)
                # ... but neither ccache nor a C++ ABI
                @test !occursin("ccache", script)
                @test !occursin("CCACHE", script)
                @test !occursin("_GLIBCXX_USE_CXX11_ABI", script)
            end

            env = toolchain_env(ft, "/opt/toolchain")
            for prefix in ("HOST", "HOST_", "")
                @test env["$(prefix)FC"] == "host-$(t)-gfortran"
                @test env["$(prefix)F77"] == "host-$(t)-f77"
            end
            @test split(env["PATH"], ":") == ["/opt/toolchain/wrappers", "/opt/toolchain/gcc/bin"]
        end

        # The cache key covers what the wrappers depend on
        keys = [BinaryBuilderToolchains.cache_key(FortranToolchain(native; kwargs...)) for kwargs in (
            (;), (; vendor=:gcc_bootstrap), (; lock_microarchitecture=false), (; extra_fflags=["-I/x"]),
            (; extra_ldflags=["-L/x"]), (; env_prefixes=["HOST"]), (; wrapper_prefixes=["host-"]),
        )]
        @test allunique(keys)
        @test BinaryBuilderToolchains.cache_key(FortranToolchain(native)) == first(keys)
        @test startswith(first(keys), "FortranToolchain-")
    end

    # Build and run Fortran with a deployed toolchain.  This needs a GCC with `gfortran`,
    # which the pinned `GCC_jll` does not have yet: a toolchain universe can provide one
    # (`BINARYBUILDER_TOOLCHAIN_UNIVERSE`, see `use_toolchain_universe!()`).
    htt_toolchain = HostToolsToolchain(BBHostPlatform())
    has_gfortran(prefix) = isfile(joinpath(prefix, "gcc", "bin", "$(native_triplet)-gfortran"))
    # Our `libgfortran`, for the programs that link it dynamically
    runtime_env(prefix, env) = path_appending_merge(env, Dict("LD_LIBRARY_PATH" => joinpath(prefix, "gcc", native_triplet, "lib64")))

    @testset "testsuite" begin
        toolchains = [CToolchain(native; use_ccache=false), FortranToolchain(native), CMakeToolchain(native), htt_toolchain]
        with_toolchains(toolchains) do prefix, env
            if !has_gfortran(prefix)
                @warn("The deployed GCC has no gfortran, skipping the FortranToolchain test suite")
                @test_skip has_gfortran(prefix)
                return
            end
            toolchain_tests(prefix, runtime_env(prefix, env), native, "FortranToolchain")
        end
    end

    # As for the C toolchain, deploy a host and a target toolchain, each with the flags of
    # its own install prefix (as a build does with `alter_toolchain()`), and check that each
    # finds its own prefix's modules and libraries
    @testset "target/host isolation" begin
        mktempdir() do dir
            host_prefix = joinpath(dir, "host")
            target_prefix = joinpath(dir, "target")
            prefix_flags(p) = (; extra_fflags=["-I$(p)/include"], extra_ldflags=["-L$(p)/lib"])
            host_toolchains = [
                CToolchain(native; env_prefixes=["HOST_"], wrapper_prefixes=["host-"], use_ccache=false),
                FortranToolchain(native; env_prefixes=["HOST_"], wrapper_prefixes=["host-"], prefix_flags(host_prefix)...),
                htt_toolchain,
            ]
            # (The host's `gcc/bin`, on `PATH` before the target's wrappers, has an unwrapped
            # `<triplet>-gfortran`: name the target's wrappers as a build does, `target-...`)
            target_toolchains = [
                CToolchain(native; use_ccache=false),
                FortranToolchain(native; wrapper_prefixes=["target-\${triplet}-", "\${triplet}-", ""], prefix_flags(target_prefix)...),
            ]
            with_toolchains(host_toolchains) do host_tc_prefix, host_env
                with_toolchains(target_toolchains) do target_tc_prefix, target_env
                    if !has_gfortran(host_tc_prefix) || !has_gfortran(target_tc_prefix)
                        @test_skip has_gfortran(host_tc_prefix)
                        return
                    end
                    env = runtime_env(target_tc_prefix, path_appending_merge(host_env, target_env))
                    @test env["HOST_FC"] == "host-gfortran"
                    @test env["FC"] == "target-$(native_triplet)-gfortran"
                    function sh(script)
                        p, output = capture_output(setenv(Cmd(["/bin/bash", "-c", script]), env))
                        success(p) || println(output)
                        return success(p)
                    end
                    # Install a module and a library with a different version into each prefix ...
                    for (fc, prefix, version) in (("\${HOST_FC}", host_prefix, 1), ("\${FC}", target_prefix, 2))
                        mkpath(joinpath(prefix, "include"))
                        mkpath(joinpath(prefix, "lib"))
                        src = joinpath(dir, "versioned_$(version).f90")
                        write(src, """
                            module versioned
                                implicit none
                                integer, parameter :: version = $(version)
                            contains
                                integer function lib_version()
                                    lib_version = $(version)
                                end function lib_version
                            end module versioned
                            """)
                        @test sh("cd $(dir) && $(fc) -c -fPIC -J$(prefix)/include -o $(prefix)/versioned.o $(src) && " *
                                 "$(fc) -shared -o $(prefix)/lib/libversioned.so $(prefix)/versioned.o")
                        @test isfile(joinpath(prefix, "include", "versioned.mod"))
                    end
                    # ... then use them without saying where they are
                    user = joinpath(dir, "user.f90")
                    write(user, """
                        program user
                            use versioned, only: version, lib_version
                            implicit none
                            write(*, '(i0,1x,i0)') version, lib_version()
                        end program user
                        """)
                    for (fc, prefix, version) in (("\${HOST_FC}", host_prefix, 1), ("\${FC}", target_prefix, 2))
                        exe = joinpath(dir, "user_$(version)")
                        @test sh("cd $(dir) && $(fc) -o $(exe) $(user) -lversioned -Wl,-rpath,$(prefix)/lib")
                        @test readchomp(setenv(`$(exe)`, env)) == "$(version) $(version)"
                    end
                end
            end
        end
    end
end
