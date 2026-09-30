using JLLGenerator
export AuditInfo, AuditDependencyInfo

struct AuditDependencyInfo
    # library products of the JLL, for the platform being audited
    libs::Vector{JLLLibraryProduct}
end

struct AuditLibraryInfo
    # The JLL's package name, e.g. `:Zlib_jll`
    jll_name::Symbol
    # Product varname providing this library
    varname::Symbol
    # Relative to that JLL's prefix, path to library
    path::String
end

# Information about the context for an audit, including JLL dependencies
# and SONAME / libraries within them.
struct AuditInfo
    # Each dependency, by its package name (`:Zlib_jll`), which is how the record names it
    deps::Dict{Symbol,AuditDependencyInfo}
    sonames::Dict{String,AuditLibraryInfo}
end

function AuditInfo(deps::Dict{Symbol,AuditDependencyInfo})
    sonames = Dict{String,AuditLibraryInfo}()
    for (jll_name, dep) in deps, lib in dep.libs
        sonames[basename(lib.soname)] = AuditLibraryInfo(jll_name, lib.varname, lib.path)
    end
    return AuditInfo(deps, sonames)
end
AuditInfo() = AuditInfo(Dict{Symbol,AuditDependencyInfo}())
