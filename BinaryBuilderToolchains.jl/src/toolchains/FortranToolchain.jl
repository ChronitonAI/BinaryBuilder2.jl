export FortranToolchain

"""
    FortranToolchain(platform::CrossPlatform; vendor = :auto, ...)

A Fortran compiler, GCC's `gfortran`, for `platform`, with wrappers named `gfortran` and
`f77` (prefixed like a `CToolchain`'s, e.g. `x86_64-linux-gnu-gfortran`) and `FC` and `F77`
pointing at them, for each of `env_prefixes` (`FC`, `HOSTFC`, `HOST_FC`, ...).  It is meant
to be used next to a `CToolchain` for the same platform, which provides the binutils
wrappers and C compilers (recipes that mix C and Fortran, and `configure` scripts, want
both); it installs the whole GCC that `gfortran` belongs to, with its runtime libraries
(`libgfortran`, `libquadmath`), sysroot and binutils, from the same JLLs a `CToolchain`
with the GCC vendor installs, which merge with those when both are installed in one prefix
(`deduplicate_jlls()`).

Keyword arguments:
 - `vendor`: `:gcc` (the default, also on platforms whose `CToolchain` defaults to clang)
   or `:gcc_bootstrap`, the GCC of a `CToolchain(; vendor = :gcc_bootstrap)`.  Use the
   same GCC as the `CToolchain` next to it: both install it under `gcc/`.
 - `env_prefixes`, `wrapper_prefixes`, `lock_microarchitecture`, `glibc_version`: as for a
   `CToolchain` (they must match the `CToolchain`'s to share its JLLs).
 - `extra_fflags`, `extra_ldflags`: flags added to each compilation (and so the module
   search path, given `-I`) and to each link.

The wrappers do not use `ccache`, which cannot cache Fortran.  GCC 14's `libgfortran` is
`libgfortran5`, the only `libgfortran_version` a target can ask for (see
`expand_gfortran_versions()`).

On a software ticks platform (`rr_softticks`), the wrappers load the software ticks plugin
(`GCCSoftTicksPlugin_jll`, which the toolchain installs) into `gfortran` and define
`__RR_SOFTTICKS__`, as the C toolchain's do (`add_softticks_flags()`); the wrapper's
definition is the only one there, as the plugin defines the macro in the C family's
preprocessor only.
"""
struct FortranToolchain <: AbstractToolchain
    platform::CrossPlatform

    # `:gcc` or `:gcc_bootstrap`
    vendor::Symbol
    deps::Vector{JLLSource}

    # See `CToolchain` for these
    wrapper_prefixes::Vector{String}
    env_prefixes::Vector{String}
    lock_microarchitecture::Bool
    extra_fflags::Vector{String}
    extra_ldflags::Vector{String}

    # The version of the GCC we install (`nothing` if it is not known)
    gcc_version::Union{Nothing,VersionNumber}

    # Cache key that we use to store our generated wrappers
    cache_key::String

    function FortranToolchain(platform::CrossPlatform;
                              vendor = :auto,
                              env_prefixes = [""],
                              wrapper_prefixes = ["\${triplet}-", ""],
                              lock_microarchitecture = true,
                              glibc_version = :oldest,
                              extra_fflags = String[],
                              extra_ldflags = String[])
        valid_vendors = (:auto, :gcc, :bootstrap, :gcc_bootstrap)
        if vendor ∉ valid_vendors
            throw(ArgumentError("Invalid value '$(vendor)' for `vendor`, must be one of $(valid_vendors) (gfortran comes with GCC)"))
        end
        # Unlike a `CToolchain`'s, our default is GCC everywhere
        vendor = vendor == :auto ? :gcc : vendor == :bootstrap ? :gcc_bootstrap : vendor

        if isempty(wrapper_prefixes)
            throw(ArgumentError("Cannot have empty wrapper prefixes!  Did you mean [\"\"]?"))
        end
        if isempty(env_prefixes)
            throw(ArgumentError("Cannot have empty env prefixes!  Did you mean [\"\"]?"))
        end

        # We only have GCC 14, which only builds against `libgfortran5`
        gfortran_version = libgfortran_version(platform.target)
        if gfortran_version !== nothing && gfortran_version.major != 5
            throw(ArgumentError("FortranToolchain only provides libgfortran5 (GCC 14), not libgfortran_version=$(gfortran_version) ($(triplet(platform.target)))"))
        end

        # The JLLs of the GCC that a `CToolchain` with this vendor installs, along with the
        # binutils that its drivers run: identical to the `CToolchain`'s, so that they merge
        deps = JLLSource[
            compiler_jlls(
                vendor,
                platform,
                VersionSpec("9"),
                VersionSpec("17"),
                resolve_glibc_version(glibc_version, platform),
                false,
                :auto,
                :auto,
            )...,
            binutils_jlls(vendor, platform)...,
        ]
        gcc_version = installed_gcc_version(deps)

        wrapper_prefixes = string.(wrapper_prefixes)
        env_prefixes = string.(env_prefixes)
        extra_fflags = string.(extra_fflags)
        extra_ldflags = string.(extra_ldflags)
        cache_key = string(
            "FortranToolchain-",
            bytes2hex(sha1(repr((
                triplet(platform),
                vendor,
                lock_microarchitecture,
                gcc_version,
                env_prefixes,
                wrapper_prefixes,
                extra_fflags,
                extra_ldflags,
                # The software ticks flags the wrappers add (`add_softticks_flags()`): bump
                # the version when they change, so that cached wrappers are regenerated.
                rr_softticks(platform.target) === nothing ? "" : "softticks-fortran-wrappers-1",
            )))),
        )

        return new(
            platform,
            vendor,
            deps,
            wrapper_prefixes,
            env_prefixes,
            lock_microarchitecture,
            extra_fflags,
            extra_ldflags,
            gcc_version,
            cache_key,
        )
    end
end

cache_key(toolchain::FortranToolchain) = toolchain.cache_key
extra_compile_flags(toolchain::FortranToolchain) = toolchain.extra_fflags
platform(toolchain::FortranToolchain) = toolchain.platform

function Base.show(io::IO, toolchain::FortranToolchain)
    println(io, "FortranToolchain ($(toolchain.platform))")
    for dep in toolchain.deps
        println(io, " - $(dep.package.name[1:end-4]) v$(dep.package.version)")
    end
end

"""
    gfortran_wrappers(toolchain::FortranToolchain, dir::String)

Generate the `gfortran` and `f77` wrapper scripts (using `compiler_wrapper()`) into `dir`,
both launching `GCC_jll`'s `gfortran` with the flags of the C toolchain's `gcc` wrappers
(`add_gcc_driver_flags()`), but no C++ ABI define and no `ccache`.
"""
function gfortran_wrappers(toolchain::FortranToolchain, dir::String)
    toolchain_prefix = "\$(dirname \"\${WRAPPER_DIR}\")/gcc"
    gcc_version = something(toolchain.gcc_version, v"0")

    _gfortran_wrapper(io) = add_gcc_driver_flags(io, toolchain, toolchain_prefix, gcc_version; cxxabi=false, ccache=false)

    gfortran = string(gcc_driver_triplet(toolchain), "-gfortran")
    make_tool_wrappers(toolchain, dir, "gfortran", gfortran; wrapper=_gfortran_wrapper, toolchain_prefix)
    make_tool_wrappers(toolchain, dir, "f77", gfortran; wrapper=_gfortran_wrapper, toolchain_prefix)
end

function toolchain_sources(toolchain::FortranToolchain)
    sources = AbstractSource[]
    push!(sources, CachedGeneratedSource(cache_key(toolchain); target="wrappers") do out_dir
        gfortran_wrappers(toolchain, out_dir)
    end)
    append!(sources, toolchain.deps)
    return sources
end

function toolchain_env(toolchain::FortranToolchain, deployed_prefix::String)
    env = Dict{String,String}()
    insert_PATH!(env, :PRE, [
        joinpath(deployed_prefix, "wrappers"),
        joinpath(deployed_prefix, "gcc", "bin"),
    ])

    # We can have multiple wrapper prefixes, we always use the longest one
    # as that's typically the most specific.
    wrapper_prefixes = replace.(toolchain.wrapper_prefixes, ("\${triplet}" => triplet(gcc_platform(toolchain.platform.target)),))
    wrapper_prefix = wrapper_prefixes[argmax(length.(wrapper_prefixes))]
    for env_prefix in toolchain.env_prefixes
        env["$(env_prefix)FC"] = "$(wrapper_prefix)gfortran"
        env["$(env_prefix)F77"] = "$(wrapper_prefix)f77"
    end
    return env
end

# The same platforms as the C toolchain's GCC
supported_platforms(::Type{FortranToolchain}; experimental::Bool = false) = supported_platforms(CToolchain; experimental)
